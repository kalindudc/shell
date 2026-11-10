/**
 * Web search providers and routing.
 *
 *   duckduckgo  keyless HTML endpoint (lite endpoint as fallback); fast, keyword-style
 *   exa         keyless Exa MCP endpoint (JSON-RPC over HTTPS); semantic, rich highlights
 *   brave       Brave Search API (BRAVE_API_KEY / braveApiKey)
 *   searxng     self-hosted SearXNG with JSON format (SEARXNG_URL / searxngUrl)
 *
 * `auto` tries brave → searxng → duckduckgo → exa, skipping unconfigured
 * providers and falling through on errors (e.g. DuckDuckGo's bot check).
 * Keyless providers get a small per-process concurrency cap so batch queries
 * do not trip their rate limits. Every response records which provider
 * answered and any attempts that failed, so the agent can see what happened.
 */

import type { PiWebConfig, SearchProviderName } from "./config.ts";
import { decodeEntities, htmlToText } from "./html.ts";
import { NetError, createLimiter, mimeType, readBodyLimited, safeFetch } from "./net.ts";

export type Recency = "day" | "week" | "month" | "year";
export const RECENCY_VALUES = ["day", "week", "month", "year"] as const;

export interface SearchResult {
	title: string;
	url: string;
	snippet: string;
	/** Provider-supplied age/date hint, when available. */
	age?: string;
}

export interface SearchOptions {
	numResults: number;
	recency?: Recency;
	/** Domain filters; prefix with "-" to exclude. */
	domains?: string[];
	signal?: AbortSignal;
}

export interface SearchAttempt {
	provider: Exclude<SearchProviderName, "auto">;
	error: string;
	durationMs: number;
}

export interface SearchResponse {
	query: string;
	provider: Exclude<SearchProviderName, "auto">;
	results: SearchResult[];
	durationMs: number;
	/** Providers that were tried before `provider` succeeded. */
	attempts: SearchAttempt[];
	/** Total results the provider returned before domain filtering / truncation. */
	rawCount: number;
	/** Caveats worth surfacing (e.g. provider ignored the recency filter). */
	note?: string;
}

type ConcreteProvider = Exclude<SearchProviderName, "auto">;

// ---------------------------------------------------------------------------
// Domain filtering
// ---------------------------------------------------------------------------

export interface DomainFilters {
	allow: string[];
	deny: string[];
}

export function parseDomainFilters(domains: string[] | undefined): DomainFilters {
	const filters: DomainFilters = { allow: [], deny: [] };
	for (const raw of domains ?? []) {
		const trimmed = raw.trim();
		if (!trimmed) continue;
		const deny = trimmed.startsWith("-");
		let host = trimmed.replace(/^-/, "").replace(/^https?:\/\//i, "").replace(/^\*\./, "").replace(/^www\./i, "");
		host = host.split("/")[0]!.toLowerCase();
		if (!host) continue;
		const target = deny ? filters.deny : filters.allow;
		if (!target.includes(host)) target.push(host);
	}
	return filters;
}

function hostMatches(hostname: string, domain: string): boolean {
	return hostname === domain || hostname.endsWith(`.${domain}`);
}

export function matchesDomainFilters(url: string, filters: DomainFilters): boolean {
	if (filters.allow.length === 0 && filters.deny.length === 0) return true;
	let hostname: string;
	try {
		hostname = new URL(url).hostname.toLowerCase().replace(/^www\./, "");
	} catch {
		return false;
	}
	if (filters.allow.length > 0 && !filters.allow.some((d) => hostMatches(hostname, d))) return false;
	return !filters.deny.some((d) => hostMatches(hostname, d));
}

/** Append `site:` operators when the filter is a single allow-list domain (well supported everywhere). */
function applySiteOperator(query: string, filters: DomainFilters): string {
	if (/\bsite:/i.test(query)) return query;
	const parts: string[] = [];
	if (filters.allow.length === 1) parts.push(`site:${filters.allow[0]}`);
	for (const d of filters.deny.slice(0, 3)) parts.push(`-site:${d}`);
	return parts.length ? `${query} ${parts.join(" ")}` : query;
}

function finalizeResults(results: SearchResult[], options: SearchOptions): { results: SearchResult[]; rawCount: number } {
	const filters = parseDomainFilters(options.domains);
	const seen = new Set<string>();
	const out: SearchResult[] = [];
	for (const r of results) {
		const key = r.url.replace(/^https?:\/\/(www\.)?/, "").replace(/\/+$/, "").toLowerCase();
		if (seen.has(key)) continue;
		seen.add(key);
		if (!matchesDomainFilters(r.url, filters)) continue;
		out.push(r);
		if (out.length >= options.numResults) break;
	}
	return { results: out, rawCount: results.length };
}

// ---------------------------------------------------------------------------
// DuckDuckGo
// ---------------------------------------------------------------------------

const DDG_HTML_URL = "https://html.duckduckgo.com/html/";
const DDG_LITE_URL = "https://lite.duckduckgo.com/lite/";
const DDG_RECENCY: Record<Recency, string> = { day: "d", week: "w", month: "m", year: "y" };

/** Decode DuckDuckGo redirect links (//duckduckgo.com/l/?uddg=<encoded>) to the destination URL. */
export function decodeDuckDuckGoUrl(href: string): string | null {
	try {
		const link = new URL(href, DDG_HTML_URL);
		const target = link.searchParams.get("uddg");
		const url = new URL(target ?? link.href);
		if (url.protocol !== "http:" && url.protocol !== "https:") return null;
		if (/(^|\.)duckduckgo\.com$/.test(url.hostname) && url.pathname.startsWith("/y.js")) return null; // ad tracker
		return url.href;
	} catch {
		return null;
	}
}

function detectDuckDuckGoBlock(html: string, status: number): string | null {
	if (status === 202 || /anomaly-modal|class="anomaly|bots use DuckDuckGo too|If this error persists/i.test(html)) {
		return "DuckDuckGo is rate-limiting this client (bot check). Wait a moment and retry, or configure Brave/SearXNG.";
	}
	if (status === 403) return "DuckDuckGo returned 403 Forbidden (blocked).";
	return null;
}

/** Parse the html.duckduckgo.com results page. */
export function parseDuckDuckGoHtml(html: string): SearchResult[] {
	const results: SearchResult[] = [];
	// Split on result containers. Each block runs until the next one.
	const blocks = html.split(/<div[^>]+class="[^"]*\bresult\b[^"]*results_links[^"]*"/i).slice(1);
	for (const block of blocks) {
		if (/\bresult--ad\b|\bresult__sponsored\b/i.test(block.slice(0, 400))) continue;
		const anchor = /<a[^>]+class="[^"]*\bresult__a\b[^"]*"[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>/i.exec(block)
			?? /<a[^>]+href="([^"]+)"[^>]+class="[^"]*\bresult__a\b[^"]*"[^>]*>([\s\S]*?)<\/a>/i.exec(block);
		if (!anchor) continue;
		const url = decodeDuckDuckGoUrl(decodeEntities(anchor[1] ?? ""));
		const title = htmlToText(anchor[2] ?? "");
		if (!url || !title) continue;
		const snippetMatch = /<(?:a|div)[^>]+class="[^"]*\bresult__snippet\b[^"]*"[^>]*>([\s\S]*?)<\/(?:a|div)>/i.exec(block);
		const snippet = snippetMatch ? htmlToText(snippetMatch[1] ?? "") : "";
		results.push({ title, url, snippet });
	}
	return results;
}

/** Parse the lite.duckduckgo.com results page (table layout). */
export function parseDuckDuckGoLite(html: string): SearchResult[] {
	const results: SearchResult[] = [];
	const linkRe = /<a[^>]+class=['"]result-link['"][^>]*href=['"]([^'"]+)['"][^>]*>([\s\S]*?)<\/a>|<a[^>]+href=['"]([^'"]+)['"][^>]*class=['"]result-link['"][^>]*>([\s\S]*?)<\/a>/gi;
	const snippetRe = /<td[^>]+class=['"]result-snippet['"][^>]*>([\s\S]*?)<\/td>/gi;
	const links: Array<{ url: string; title: string; index: number }> = [];
	let m: RegExpExecArray | null;
	while ((m = linkRe.exec(html)) !== null) {
		const url = decodeDuckDuckGoUrl(decodeEntities(m[1] ?? m[3] ?? ""));
		const title = htmlToText(m[2] ?? m[4] ?? "");
		if (url && title) links.push({ url, title, index: m.index });
	}
	const snippets: Array<{ text: string; index: number }> = [];
	while ((m = snippetRe.exec(html)) !== null) snippets.push({ text: htmlToText(m[1] ?? ""), index: m.index });
	for (let i = 0; i < links.length; i++) {
		const link = links[i]!;
		const next = links[i + 1]?.index ?? Number.POSITIVE_INFINITY;
		const snippet = snippets.find((s) => s.index > link.index && s.index < next)?.text ?? "";
		results.push({ title: link.title, url: link.url, snippet });
	}
	return results;
}

async function fetchText(
	url: string,
	config: PiWebConfig,
	signal: AbortSignal | undefined,
	headers: Record<string, string>,
	init: { method?: "GET" | "POST"; body?: string } = {},
): Promise<{ status: number; text: string; contentType: string }> {
	const { response } = await safeFetch(url, {
		signal,
		timeoutMs: config.timeoutMs,
		maxBytes: config.maxResponseBytes,
		headers: { "User-Agent": config.userAgent, "Accept-Language": "en-US,en;q=0.9", ...headers },
		method: init.method,
		body: init.body,
	});
	const bytes = await readBodyLimited(response, config.maxResponseBytes, signal);
	return { status: response.status, text: new TextDecoder().decode(bytes), contentType: response.headers.get("content-type") ?? "" };
}

async function searchDuckDuckGo(query: string, options: SearchOptions, config: PiWebConfig): Promise<SearchResult[]> {
	const q = applySiteOperator(query, parseDomainFilters(options.domains));
	const htmlUrl = new URL(DDG_HTML_URL);
	htmlUrl.searchParams.set("q", q);
	htmlUrl.searchParams.set("kl", "wt-wt");
	if (options.recency) htmlUrl.searchParams.set("df", DDG_RECENCY[options.recency]);

	const primary = await fetchText(htmlUrl.href, config, options.signal, { Accept: "text/html" });
	const blocked = detectDuckDuckGoBlock(primary.text, primary.status);
	let results = primary.status === 200 && !blocked ? parseDuckDuckGoHtml(primary.text) : [];
	if (results.length > 0) return results;

	// Fallback: lite endpoint (different backend path, sometimes not rate-limited when html is)
	const liteUrl = new URL(DDG_LITE_URL);
	liteUrl.searchParams.set("q", q);
	liteUrl.searchParams.set("kl", "wt-wt");
	if (options.recency) liteUrl.searchParams.set("df", DDG_RECENCY[options.recency]);
	const lite = await fetchText(liteUrl.href, config, options.signal, { Accept: "text/html" });
	const liteBlocked = detectDuckDuckGoBlock(lite.text, lite.status);
	results = lite.status === 200 && !liteBlocked ? parseDuckDuckGoLite(lite.text) : [];
	if (results.length > 0) return results;

	if (blocked || liteBlocked) throw new Error(blocked ?? liteBlocked ?? "blocked");
	if (primary.status !== 200) throw new Error(`DuckDuckGo returned HTTP ${primary.status}`);
	if (/no results\.?<\/|No results found|did not match any/i.test(primary.text + lite.text)) return [];
	if (!/result__a|result-link/i.test(primary.text + lite.text)) {
		throw new Error("DuckDuckGo returned an unrecognized page (layout may have changed)");
	}
	return [];
}

// ---------------------------------------------------------------------------
// Exa (keyless MCP endpoint)
// ---------------------------------------------------------------------------

const EXA_MCP_URL = "https://mcp.exa.ai/mcp?tools=web_search_exa";

interface JsonRpcResponse {
	result?: { isError?: boolean; content?: Array<{ type: string; text?: string }> };
	error?: { code?: number; message?: string };
}

/** Extract the JSON-RPC payload from a plain JSON or SSE (`data:` lines) body. */
export function parseJsonRpcBody(body: string): JsonRpcResponse | null {
	for (const line of body.split("\n")) {
		if (!line.startsWith("data:")) continue;
		try {
			const candidate = JSON.parse(line.slice(5).trim()) as JsonRpcResponse;
			if (candidate.result || candidate.error) return candidate;
		} catch {
			/* keep scanning */
		}
	}
	try {
		const candidate = JSON.parse(body) as JsonRpcResponse;
		if (candidate.result || candidate.error) return candidate;
	} catch {
		/* not JSON */
	}
	return null;
}

/**
 * Parse Exa's text blocks:
 *   Title: ...\nURL: ...\nPublished: ...\nAuthor: ...\nHighlights:\n> ...\n...\n(or Text: ...)
 */
export function parseExaText(text: string): SearchResult[] {
	const results: SearchResult[] = [];
	for (const block of text.split(/(?=^Title: )/m)) {
		const title = /^Title:\s*(.+)$/m.exec(block)?.[1]?.trim() ?? "";
		const url = /^URL:\s*(\S+)/m.exec(block)?.[1]?.trim() ?? "";
		if (!url || !/^https?:\/\//i.test(url)) continue;
		const published = /^Published:\s*(.+)$/m.exec(block)?.[1]?.trim();
		let bodyText = "";
		const hl = /^Highlights:\s*\n([\s\S]*)$/m.exec(block);
		const tx = /^Text:\s*([\s\S]*)$/m.exec(block);
		if (hl?.[1]) bodyText = hl[1];
		else if (tx?.[1]) bodyText = tx[1];
		const snippet = bodyText
			.split("\n")
			.map((l) => l.replace(/^>\s?/, "").trim())
			.filter((l) => l && l !== "..." && l !== "---")
			.join(" ")
			.replace(/\s+/g, " ")
			.slice(0, 600);
		results.push({
			title: title || url,
			url,
			snippet,
			age: published && !/^n\/a$/i.test(published) ? published.slice(0, 10) : undefined,
		});
	}
	return results;
}

async function searchExa(query: string, options: SearchOptions, config: PiWebConfig): Promise<SearchResult[]> {
	const filters = parseDomainFilters(options.domains);
	const wantsFilter = filters.allow.length > 0 || filters.deny.length > 0;
	const body = JSON.stringify({
		jsonrpc: "2.0",
		id: 1,
		method: "tools/call",
		params: {
			name: "web_search_exa",
			arguments: {
				query: filters.allow.length === 1 ? `${query} (from ${filters.allow[0]})` : query,
				numResults: Math.min(20, wantsFilter ? options.numResults * 2 : options.numResults),
				objective: `Rank the most relevant, authoritative pages for: ${query}.${options.recency ? ` Prefer content from the last ${options.recency}.` : ""}`,
			},
		},
	});
	const { status, text } = await fetchText(EXA_MCP_URL, config, options.signal, {
		"Content-Type": "application/json",
		Accept: "application/json, text/event-stream",
		"x-exa-source": "pi-web",
	}, { method: "POST", body });
	if (status === 429) throw new Error("Exa (keyless) rate limit reached (HTTP 429) — retry in a moment");
	if (status !== 200) throw new Error(`Exa MCP returned HTTP ${status}: ${text.slice(0, 200)}`);
	const rpc = parseJsonRpcBody(text);
	if (!rpc) throw new Error("Exa MCP returned an unrecognized response");
	if (rpc.error) throw new Error(`Exa MCP error${rpc.error.code ? ` ${rpc.error.code}` : ""}: ${rpc.error.message ?? "unknown"}`);
	const content = rpc.result?.content?.find((c) => c.type === "text" && typeof c.text === "string")?.text ?? "";
	if (rpc.result?.isError) throw new Error(content.trim().slice(0, 300) || "Exa MCP returned an error");
	if (!content.trim()) return [];
	return parseExaText(content);
}

// ---------------------------------------------------------------------------
// Brave
// ---------------------------------------------------------------------------

const BRAVE_URL = "https://api.search.brave.com/res/v1/web/search";
const BRAVE_RECENCY: Record<Recency, string> = { day: "pd", week: "pw", month: "pm", year: "py" };

interface BraveResponse {
	web?: { results?: Array<{ title?: string; url?: string; description?: string; age?: string; page_age?: string }> };
	news?: { results?: Array<{ title?: string; url?: string; description?: string; age?: string }> };
}

export function parseBraveResponse(payload: unknown): SearchResult[] {
	const data = payload as BraveResponse;
	const out: SearchResult[] = [];
	for (const r of data.web?.results ?? []) {
		if (!r.url || !r.title) continue;
		out.push({ title: htmlToText(r.title), url: r.url, snippet: htmlToText(r.description ?? ""), age: r.age ?? r.page_age?.slice(0, 10) });
	}
	for (const r of data.news?.results ?? []) {
		if (!r.url || !r.title) continue;
		out.push({ title: htmlToText(r.title), url: r.url, snippet: htmlToText(r.description ?? ""), age: r.age });
	}
	return out;
}

async function searchBrave(query: string, options: SearchOptions, config: PiWebConfig): Promise<SearchResult[]> {
	if (!config.braveApiKey) throw new Error("Brave is not configured (set BRAVE_API_KEY or braveApiKey in pi-web.json)");
	const filters = parseDomainFilters(options.domains);
	const url = new URL(BRAVE_URL);
	url.searchParams.set("q", applySiteOperator(query, filters));
	url.searchParams.set("count", String(Math.min(20, Math.max(options.numResults, filters.allow.length || filters.deny.length ? 20 : options.numResults))));
	url.searchParams.set("text_decorations", "false");
	url.searchParams.set("safesearch", "moderate");
	if (options.recency) url.searchParams.set("freshness", BRAVE_RECENCY[options.recency]);

	const { status, text, contentType } = await fetchText(url.href, config, options.signal, {
		Accept: "application/json",
		"Accept-Encoding": "gzip",
		"X-Subscription-Token": config.braveApiKey,
	});
	if (status === 401 || status === 403) throw new Error(`Brave rejected the API key (HTTP ${status})`);
	if (status === 429) throw new Error("Brave rate limit exceeded (HTTP 429)");
	if (status !== 200) throw new Error(`Brave returned HTTP ${status}: ${text.slice(0, 200)}`);
	if (!mimeType(contentType).includes("json")) throw new Error("Brave returned a non-JSON response");
	return parseBraveResponse(JSON.parse(text));
}

// ---------------------------------------------------------------------------
// SearXNG
// ---------------------------------------------------------------------------

interface SearxngResponse {
	results?: Array<{ title?: string; url?: string; content?: string; publishedDate?: string | null; engine?: string }>;
}

export function parseSearxngResponse(payload: unknown): SearchResult[] {
	const data = payload as SearxngResponse;
	const out: SearchResult[] = [];
	for (const r of data.results ?? []) {
		if (!r.url || !r.title) continue;
		out.push({ title: htmlToText(r.title), url: r.url, snippet: htmlToText(r.content ?? ""), age: r.publishedDate?.slice(0, 10) ?? undefined });
	}
	return out;
}

async function searchSearxng(query: string, options: SearchOptions, config: PiWebConfig): Promise<SearchResult[]> {
	if (!config.searxngUrl) throw new Error("SearXNG is not configured (set SEARXNG_URL or searxngUrl in pi-web.json)");
	const url = new URL(`${config.searxngUrl}/search`);
	url.searchParams.set("q", applySiteOperator(query, parseDomainFilters(options.domains)));
	url.searchParams.set("format", "json");
	if (options.recency) url.searchParams.set("time_range", options.recency);

	const { response } = await safeFetch(url.href, {
		signal: options.signal,
		timeoutMs: config.timeoutMs,
		maxBytes: config.maxResponseBytes,
		headers: { "User-Agent": config.userAgent, Accept: "application/json" },
		// A self-hosted SearXNG is very often on a private address.
		allowPrivateNetwork: true,
	});
	const text = new TextDecoder().decode(await readBodyLimited(response, config.maxResponseBytes, options.signal));
	if (response.status === 403) throw new Error("SearXNG returned 403 — enable `json` in the instance's `search.formats` setting");
	if (response.status !== 200) throw new Error(`SearXNG returned HTTP ${response.status}: ${text.slice(0, 200)}`);
	return parseSearxngResponse(JSON.parse(text));
}

// ---------------------------------------------------------------------------
// Routing
// ---------------------------------------------------------------------------

const PROVIDERS: Record<ConcreteProvider, (q: string, o: SearchOptions, c: PiWebConfig) => Promise<SearchResult[]>> = {
	duckduckgo: searchDuckDuckGo,
	exa: searchExa,
	brave: searchBrave,
	searxng: searchSearxng,
};

/** Keyless endpoints are shared by everyone; keep our burst small. */
const PROVIDER_LIMITERS: Partial<Record<ConcreteProvider, ReturnType<typeof createLimiter>>> = {
	duckduckgo: createLimiter(2),
	exa: createLimiter(2),
};

const SUPPORTS_RECENCY: Record<ConcreteProvider, boolean> = { duckduckgo: true, exa: false, brave: true, searxng: true };

export function isProviderConfigured(provider: ConcreteProvider, config: PiWebConfig): boolean {
	if (provider === "brave") return Boolean(config.braveApiKey);
	if (provider === "searxng") return Boolean(config.searxngUrl);
	return true;
}

/** Ordered list of providers to try for a request. */
export function resolveProviderChain(requested: SearchProviderName | undefined, config: PiWebConfig): ConcreteProvider[] {
	const want = requested ?? config.provider;
	if (want !== "auto") return [want];
	const chain: ConcreteProvider[] = [];
	if (config.braveApiKey) chain.push("brave");
	if (config.searxngUrl) chain.push("searxng");
	chain.push("duckduckgo", "exa");
	return chain;
}

export async function search(
	query: string,
	options: SearchOptions,
	config: PiWebConfig,
	requested?: SearchProviderName,
): Promise<SearchResponse> {
	const chain = resolveProviderChain(requested, config);
	const attempts: SearchAttempt[] = [];
	const startedAt = Date.now();

	for (const provider of chain) {
		const attemptStart = Date.now();
		try {
			const run = () => PROVIDERS[provider](query, options, config);
			const limiter = PROVIDER_LIMITERS[provider];
			const raw = await (limiter ? limiter(run) : run());
			const { results, rawCount } = finalizeResults(raw, options);
			const note = options.recency && !SUPPORTS_RECENCY[provider] ? `${provider} does not support recency filters; results are not date-restricted` : undefined;
			return { query, provider, results, durationMs: Date.now() - startedAt, attempts, rawCount, note };
		} catch (err) {
			if (options.signal?.aborted || (err instanceof NetError && err.kind === "aborted")) throw err;
			const message = err instanceof Error ? err.message : String(err);
			attempts.push({ provider, error: message, durationMs: Date.now() - attemptStart });
		}
	}

	const detail = attempts.map((a) => `${a.provider}: ${a.error}`).join("; ");
	throw new Error(`All search providers failed — ${detail}`);
}
