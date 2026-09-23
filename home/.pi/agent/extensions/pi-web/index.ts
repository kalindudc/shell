/**
 * pi-web — lightweight, zero-dependency web access for the pi coding agent.
 *
 * Tools
 *   web_search  DuckDuckGo + Exa (keyless) · Brave · SearXNG — batch queries, recency & domain filters
 *   web_fetch   URL → readable markdown / raw text / JSON / PDF (pdftotext) — paging (offset) and find
 *
 * Command
 *   /web [status|clear]   provider + cache diagnostics
 *
 * Only Node built-ins and pi's own peer packages are imported. No npm deps.
 */

import { StringEnum, Type } from "@earendil-works/pi-ai";
import {
	DEFAULT_MAX_BYTES,
	type ExtensionAPI,
	type ExtensionContext,
	defineTool,
	formatSize,
	truncateHead,
} from "@earendil-works/pi-coding-agent";
import { Box, Text } from "@earendil-works/pi-tui";
import { SEARCH_PROVIDERS, type SearchProviderName, loadConfig, maskSecret } from "./config.ts";
import {
	type FetchMode,
	type FetchedContent,
	cacheClear,
	cacheStats,
	fetchContent,
	findPassages,
	sliceContent,
} from "./fetch.ts";
import { createLimiter, formatBytes } from "./net.ts";
import { RECENCY_VALUES, type Recency, type SearchResponse, type SearchResult, isProviderConfigured, resolveProviderChain, search } from "./search.ts";

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

const MAX_QUERIES = 8;
const MAX_URLS = 10;
/** Leave headroom under pi's 50KB tool-output limit for headers/notes. */
const OUTPUT_BUDGET = DEFAULT_MAX_BYTES - 2048;

function seconds(ms: number): string {
	return `${(ms / 1000).toFixed(ms < 10_000 ? 1 : 0)}s`;
}

function num(n: number): string {
	return n.toLocaleString("en-US");
}

function domainOf(url: string): string {
	try {
		return new URL(url).hostname.replace(/^www\./, "");
	} catch {
		return url;
	}
}

function clip(text: string, max: number): string {
	return text.length > max ? `${text.slice(0, Math.max(0, max - 1))}…` : text;
}

function toList(single: unknown, many: unknown, max: number): string[] {
	const raw: unknown[] = Array.isArray(many) ? many : [];
	if (typeof single === "string") raw.unshift(single);
	const seen = new Set<string>();
	const out: string[] = [];
	for (const item of raw) {
		if (typeof item !== "string") continue;
		const trimmed = item.trim();
		if (!trimmed || seen.has(trimmed)) continue;
		seen.add(trimmed);
		out.push(trimmed);
		if (out.length >= max) break;
	}
	return out;
}

function progressBar(progress: number, width = 10): string {
	const filled = Math.max(0, Math.min(width, Math.round(progress * width)));
	return `${"█".repeat(filled)}${"░".repeat(width - filled)}`;
}

/** Enforce pi's output limit and tell the model when it bit. */
function boundOutput(text: string, hint: string): { text: string; truncated: boolean } {
	const t = truncateHead(text, { maxBytes: OUTPUT_BUDGET, maxLines: 100_000 });
	if (!t.truncated) return { text, truncated: false };
	return {
		text: `${t.content}\n\n[Output truncated at ${formatSize(t.outputBytes)} of ${formatSize(t.totalBytes)}. ${hint}]`,
		truncated: true,
	};
}

// ---------------------------------------------------------------------------
// web_search
// ---------------------------------------------------------------------------

interface SearchQueryDetail {
	query: string;
	provider: string | null;
	results: SearchResult[];
	rawCount: number;
	durationMs: number;
	error?: string;
	note?: string;
	attempts: Array<{ provider: string; error: string }>;
}

interface FetchedSummary {
	url: string;
	title: string;
	chars: number;
	shown: number;
	error?: string;
}

interface SearchDetails {
	phase?: "searching" | "fetching" | "done";
	progress?: number;
	current?: string;
	queries: SearchQueryDetail[];
	totalResults: number;
	durationMs: number;
	fetched?: FetchedSummary[];
	outputTruncated?: boolean;
}

const searchParams = Type.Object({
	query: Type.Optional(Type.String({ description: "A single search query. For research, prefer `queries` with 2-4 varied angles." })),
	queries: Type.Optional(
		Type.Array(Type.String(), {
			description: `Multiple queries run concurrently (max ${MAX_QUERIES}). Vary phrasing/scope for coverage, e.g. ["X vs Y benchmarks 2025", "X migration guide", "X known issues"].`,
		}),
	),
	numResults: Type.Optional(Type.Integer({ minimum: 1, maximum: 20, description: "Results per query (default 5, max 20)." })),
	recency: Type.Optional(StringEnum(RECENCY_VALUES, { description: "Only results from the last day/week/month/year." })),
	domains: Type.Optional(
		Type.Array(Type.String(), { description: 'Restrict to domains, e.g. ["docs.python.org"]. Prefix with "-" to exclude, e.g. ["-pinterest.com"].' }),
	),
	provider: Type.Optional(
		StringEnum(SEARCH_PROVIDERS, {
			description: "Search backend. Omit for the configured default (auto = brave → searxng → duckduckgo → exa, using whichever is configured; duckduckgo and exa need no key).",
		}),
	),
	includeContent: Type.Optional(
		Type.Boolean({ description: "Also fetch and include readable content of the top results (bounded). Slower; use when snippets are not enough." }),
	),
});

function formatSearchText(details: SearchDetails, providerLabel: string): string {
	const q = details.queries;
	const okCount = q.filter((d) => !d.error).length;
	const lines: string[] = [];
	lines.push(
		`Web search: ${q.length} ${q.length === 1 ? "query" : "queries"} · ${details.totalResults} ${details.totalResults === 1 ? "result" : "results"} · ${providerLabel} · ${seconds(details.durationMs)}${okCount < q.length ? ` · ${q.length - okCount} failed` : ""}`,
	);

	q.forEach((d, qi) => {
		lines.push("");
		const meta: string[] = [];
		if (d.provider) meta.push(d.provider);
		meta.push(seconds(d.durationMs));
		for (const a of d.attempts) meta.push(`${a.provider} failed: ${clip(a.error, 80)}`);
		lines.push(`## ${q.length > 1 ? `${qi + 1}. ` : ""}"${d.query}" — ${d.error ? "failed" : `${d.results.length} results`} (${meta.join("; ")})`);
		if (d.error) {
			lines.push(`Error: ${d.error}`);
			return;
		}
		if (d.note) lines.push(`Note: ${d.note}`);
		if (d.results.length === 0) {
			lines.push(d.rawCount > 0 ? `No results matched the domain filter (${d.rawCount} unfiltered).` : "No results. Try broader or different terms.");
			return;
		}
		d.results.forEach((r, i) => {
			lines.push("");
			lines.push(`${i + 1}. **${r.title}** — ${domainOf(r.url)}${r.age ? ` · ${r.age}` : ""}`);
			lines.push(`   ${r.url}`);
			if (r.snippet) lines.push(`   ${r.snippet}`);
		});
	});

	if (details.fetched?.length) {
		lines.push("", "---", "", `## Content from top ${details.fetched.length} result${details.fetched.length === 1 ? "" : "s"}`);
	}
	return lines.join("\n");
}

function registerWebSearch(pi: ExtensionAPI) {
	pi.registerTool(
		defineTool<typeof searchParams, SearchDetails>({
			name: "web_search",
			label: "Web Search",
			description:
				"Search the web and return ranked results with titles, URLs, and snippets. Works with no API keys (DuckDuckGo, then Exa as fallback); Brave or SearXNG are used first when configured. Supports batch queries (run concurrently), recency filters (day/week/month/year), and domain include/exclude filters. Set includeContent to also read the top pages. Follow up with web_fetch to read any result in full.",
			promptSnippet: "Search the web (keyless DuckDuckGo/Exa, or Brave/SearXNG) for ranked results with titles, URLs, snippets; batch queries + recency/domain filters.",
			promptGuidelines: [
				"Use web_search to find current information, documentation, or sources; for research prefer `queries` with 2-4 varied angles over one broad query.",
				"After web_search, use web_fetch on the most relevant URLs to read them in full rather than relying on snippets alone.",
			],
			parameters: searchParams,

			async execute(_toolCallId, params, signal, onUpdate) {
				const config = loadConfig();
				const queries = toList(params.query, params.queries, MAX_QUERIES);
				if (queries.length === 0) throw new Error("No query provided. Pass `query` or `queries`.");
				const numResults = params.numResults ?? 5;
				const recency = params.recency as Recency | undefined;
				const provider = params.provider as SearchProviderName | undefined;
				if (provider && provider !== "auto" && !isProviderConfigured(provider, config)) {
					throw new Error(
						provider === "brave"
							? "Brave is not configured. Set BRAVE_API_KEY or `braveApiKey` in ~/.pi/agent/pi-web.json, or omit `provider`."
							: "SearXNG is not configured. Set SEARXNG_URL or `searxngUrl` in ~/.pi/agent/pi-web.json, or omit `provider`.",
					);
				}
				const chain = resolveProviderChain(provider, config);
				const startedAt = Date.now();
				const limit = createLimiter(config.concurrency);
				const details: SearchDetails = { phase: "searching", progress: 0, queries: [], totalResults: 0, durationMs: 0 };
				let completed = 0;

				const report = (current?: string) => {
					onUpdate?.({
						content: [{ type: "text", text: `Searching ${completed}/${queries.length}…` }],
						details: { ...details, phase: "searching", progress: completed / queries.length, current },
					});
				};
				report(queries[0]);

				const outcomes = await Promise.all(
					queries.map((query) =>
						limit(async (): Promise<SearchQueryDetail> => {
							const t0 = Date.now();
							try {
								const res: SearchResponse = await search(query, { numResults, recency, domains: params.domains, signal }, config, provider);
								return { query, provider: res.provider, results: res.results, rawCount: res.rawCount, durationMs: res.durationMs, attempts: res.attempts, note: res.note };
							} catch (err) {
								if (signal?.aborted) throw err;
								return { query, provider: null, results: [], rawCount: 0, durationMs: Date.now() - t0, error: err instanceof Error ? err.message : String(err), attempts: [] };
							} finally {
								completed++;
								report(query);
							}
						}),
					),
				);

				details.queries = outcomes;
				details.totalResults = outcomes.reduce((n, d) => n + d.results.length, 0);
				details.durationMs = Date.now() - startedAt;

				if (outcomes.every((d) => d.error)) {
					const reasons = [...new Set(outcomes.map((d) => d.error))].join(" | ");
					throw new Error(`Search failed for all ${queries.length === 1 ? "query" : `${queries.length} queries`}: ${reasons}`);
				}

				const usedProviders = [...new Set(outcomes.map((d) => d.provider).filter((p): p is string => Boolean(p)))];
				const providerLabel = usedProviders.join("+") || chain.join("→");
				let text = formatSearchText(details, providerLabel);

				// Optional: fetch content of top results
				if (params.includeContent && details.totalResults > 0) {
					const seen = new Set<string>();
					const targets: SearchResult[] = [];
					for (const d of outcomes) {
						for (const r of d.results) {
							const key = r.url.replace(/^https?:\/\/(www\.)?/, "").replace(/\/$/, "");
							if (seen.has(key)) continue;
							seen.add(key);
							targets.push(r);
							if (targets.length >= Math.min(3, Math.max(1, numResults))) break;
						}
						if (targets.length >= 3) break;
					}
					details.phase = "fetching";
					onUpdate?.({ content: [{ type: "text", text: `Fetching ${targets.length} pages…` }], details: { ...details, progress: 0 } });
					const budget = Math.max(2000, Math.floor((OUTPUT_BUDGET - text.length) / Math.max(1, targets.length)));
					let fetchedCount = 0;
					const pages = await Promise.all(
						targets.map((r) =>
							limit(async () => {
								const page = await fetchContent(r.url, { mode: "readable", signal, config });
								fetchedCount++;
								onUpdate?.({ content: [{ type: "text", text: `Fetched ${fetchedCount}/${targets.length} pages…` }], details: { ...details, progress: fetchedCount / targets.length, current: r.url } });
								return { r, page };
							}),
						),
					);
					details.fetched = [];
					for (const { r, page } of pages) {
						if (page.error) {
							details.fetched.push({ url: r.url, title: r.title, chars: 0, shown: 0, error: page.error });
							text += `\n\n### ${r.title}\n${r.url}\nCould not fetch: ${page.error}`;
							continue;
						}
						const slice = sliceContent(page.content, 0, budget);
						details.fetched.push({ url: r.url, title: page.title || r.title, chars: page.content.length, shown: slice.end });
						text += `\n\n### ${page.title || r.title}\n${page.finalUrl} · ${num(page.content.length)} chars${slice.truncated ? ` · showing first ${num(slice.end)} — use web_fetch with offset=${slice.end} for more` : ""}\n\n${slice.text}`;
					}
				}

				details.phase = "done";
				details.progress = 1;
				const bounded = boundOutput(text, "Use web_fetch on specific URLs for full content.");
				details.outputTruncated = bounded.truncated;
				return { content: [{ type: "text", text: bounded.text }], details };
			},

			renderCall(args, theme) {
				const queries = toList(args.query, args.queries, MAX_QUERIES);
				const head = theme.fg("toolTitle", theme.bold("web_search "));
				if (queries.length === 0) return new Text(head + theme.fg("error", "(no query)"), 0, 0);
				const opts: string[] = [];
				if (args.numResults) opts.push(`n=${args.numResults}`);
				if (args.recency) opts.push(`recency=${args.recency}`);
				if (args.domains?.length) opts.push(`domains=${args.domains.join(",")}`);
				if (args.provider && args.provider !== "auto") opts.push(`provider=${args.provider}`);
				if (args.includeContent) opts.push("+content");
				const suffix = opts.length ? theme.fg("dim", `  (${opts.join(" · ")})`) : "";
				if (queries.length === 1) return new Text(head + theme.fg("accent", `"${clip(queries[0]!, 70)}"`) + suffix, 0, 0);
				const lines = [head + theme.fg("accent", `${queries.length} queries`) + suffix];
				for (const q of queries.slice(0, 6)) lines.push(theme.fg("muted", `  "${clip(q, 64)}"`));
				if (queries.length > 6) lines.push(theme.fg("dim", `  … ${queries.length - 6} more`));
				return new Text(lines.join("\n"), 0, 0);
			},

			renderResult(result, { expanded, isPartial }, theme, context) {
				const details = result.details as SearchDetails | undefined;
				if (isPartial) {
					const p = details?.progress ?? 0;
					const phase = details?.phase === "fetching" ? "fetching pages" : "searching";
					const current = details?.current ? theme.fg("dim", ` ${clip(details.current, 50)}`) : "";
					return new Text(theme.fg("accent", `[${progressBar(p)}] ${phase}`) + current, 0, 0);
				}
				if (context.isError || !details) {
					const msg = result.content.find((c) => c.type === "text")?.text ?? "Error";
					return new Text(theme.fg("error", msg), 0, 0);
				}
				const providers = [...new Set(details.queries.map((q) => q.provider).filter(Boolean))].join("+") || "—";
				const failed = details.queries.filter((q) => q.error).length;
				let status =
					theme.fg("success", `${details.totalResults} results`) +
					theme.fg("muted", ` · ${details.queries.length} ${details.queries.length === 1 ? "query" : "queries"} · ${providers} · ${seconds(details.durationMs)}`);
				if (failed) status += theme.fg("error", ` · ${failed} failed`);
				if (details.fetched?.length) status += theme.fg("accent", ` · +${details.fetched.length} pages`);
				if (details.outputTruncated) status += theme.fg("warning", " · output truncated");

				const lines: string[] = [status];
				if (!expanded) {
					const box = new Box(1, 0);
					box.addChild(new Text(status, 0, 0));
					const preview = details.queries.flatMap((q) => q.results).slice(0, 5);
					for (const r of preview) box.addChild(new Text(theme.fg("muted", `  ▸ ${clip(r.title, 60)}`) + theme.fg("dim", ` · ${domainOf(r.url)}`), 0, 0));
					const remaining = details.totalResults - preview.length;
					const errors = details.queries.filter((q) => q.error);
					for (const e of errors.slice(0, 2)) box.addChild(new Text(theme.fg("error", `  ✗ "${clip(e.query, 40)}": ${clip(e.error ?? "", 60)}`), 0, 0));
					if (remaining > 0) box.addChild(new Text(theme.fg("dim", `  … ${remaining} more (ctrl+o to expand)`), 0, 0));
					return box;
				}
				for (const q of details.queries) {
					lines.push("");
					const meta = [q.provider ?? "—", seconds(q.durationMs), ...q.attempts.map((a) => `${a.provider} failed`)].join(" · ");
					lines.push(theme.fg("accent", `"${clip(q.query, 70)}"`) + theme.fg("dim", ` (${meta})`));
					if (q.error) {
						lines.push(theme.fg("error", `  ✗ ${q.error}`));
						continue;
					}
					q.results.forEach((r, i) => {
						lines.push(theme.fg("muted", `  ${i + 1}. ${clip(r.title, 70)}`) + theme.fg("dim", ` · ${domainOf(r.url)}${r.age ? ` · ${r.age}` : ""}`));
						lines.push(theme.fg("dim", `     ${clip(r.url, 90)}`));
						if (r.snippet) lines.push(theme.fg("dim", `     ${clip(r.snippet, 160)}`));
					});
				}
				if (details.fetched?.length) {
					lines.push("", theme.fg("accent", "Fetched content:"));
					for (const f of details.fetched) {
						lines.push(
							f.error
								? theme.fg("error", `  ✗ ${clip(f.title, 50)} — ${clip(f.error, 60)}`)
								: theme.fg("muted", `  ✓ ${clip(f.title, 50)}`) + theme.fg("dim", ` · ${num(f.shown)}/${num(f.chars)} chars · ${domainOf(f.url)}`),
						);
					}
				}
				return new Text(lines.join("\n"), 0, 0);
			},
		}),
	);
}

// ---------------------------------------------------------------------------
// web_fetch
// ---------------------------------------------------------------------------

interface FetchResultDetail {
	url: string;
	finalUrl: string;
	title: string;
	kind: string;
	status: number;
	contentType: string;
	chars: number;
	shown: number;
	offset: number;
	truncated: boolean;
	durationMs: number;
	cached: boolean;
	redirects: number;
	contentRoot?: string;
	rewrittenFrom?: string;
	warning?: string;
	error?: string;
	matches?: number;
}

interface FetchDetails {
	phase?: "fetching" | "done";
	progress?: number;
	current?: string;
	results: FetchResultDetail[];
	urlCount: number;
	successful: number;
	durationMs: number;
	mode: FetchMode;
	find?: string;
	outputTruncated?: boolean;
}

const FETCH_MODES = ["readable", "raw"] as const;

const fetchParams = Type.Object({
	url: Type.Optional(Type.String({ description: "URL to fetch (http/https; scheme optional)." })),
	urls: Type.Optional(Type.Array(Type.String(), { description: `Multiple URLs fetched concurrently (max ${MAX_URLS}); each gets a share of the output budget.` })),
	mode: Type.Optional(
		StringEnum(FETCH_MODES, {
			description: "readable (default): main content as markdown. raw: exact response body (HTML source, JSON, text).",
		}),
	),
	maxChars: Type.Optional(Type.Integer({ minimum: 200, maximum: 200_000, description: "Max characters of content to return per URL (default from config, 30000). Output is always capped at ~48KB total." })),
	offset: Type.Optional(Type.Integer({ minimum: 0, description: "Character offset to continue from (for paging long documents). Served from cache — no re-download." })),
	find: Type.Optional(
		Type.String({
			description:
				'Return only matching passages (up to 20, ~300 chars of context each, total bounded by maxChars) instead of the whole page. Plain text matches case-insensitively; use /pattern/flags for a regex (g and m are always on, so ^ and $ anchor to lines; add i for case-insensitive), e.g. find: "/^## Install/" . Great for locating a section in long docs before paging with offset.',
		}),
	),
	refresh: Type.Optional(Type.Boolean({ description: "Bypass the 15-minute cache and re-download." })),
});

function formatFetchHeader(page: FetchedContent, showTitle: boolean): string[] {
	const lines: string[] = [];
	if (showTitle && page.title) lines.push(`# ${page.title}`);
	const meta = [
		`HTTP ${page.status}`,
		page.contentType || page.kind,
		`${num(page.content.length)} chars`,
		`${seconds(page.durationMs)}${page.cached ? " (cached)" : ""}`,
	];
	if (page.redirects) meta.push(`${page.redirects} redirect${page.redirects === 1 ? "" : "s"}`);
	if (page.contentRoot && page.contentRoot !== "body") meta.push(`content: <${page.contentRoot}>`);
	lines.push(`Source: ${page.finalUrl} (${meta.join(" · ")})`);
	if (page.rewrittenFrom) lines.push(`Resolved from: ${page.rewrittenFrom}`);
	if (page.description && !page.content.includes(page.description.slice(0, 60))) lines.push(`Description: ${page.description}`);
	if (page.warning) lines.push(`Note: ${page.warning}`);
	return lines;
}

function renderFetchedPage(page: FetchedContent, opts: { offset: number; maxChars: number; find?: string; showTitle: boolean }): { text: string; detail: FetchResultDetail } {
	const base: FetchResultDetail = {
		url: page.url,
		finalUrl: page.finalUrl,
		title: page.title,
		kind: page.kind,
		status: page.status,
		contentType: page.contentType,
		chars: page.content.length,
		shown: 0,
		offset: opts.offset,
		truncated: false,
		durationMs: page.durationMs,
		cached: page.cached,
		redirects: page.redirects,
		contentRoot: page.contentRoot,
		rewrittenFrom: page.rewrittenFrom,
		warning: page.warning,
	};
	if (page.error) {
		return { text: `Source: ${page.finalUrl || page.url}\nError: ${page.error}`, detail: { ...base, error: page.error } };
	}
	const header = formatFetchHeader(page, opts.showTitle);

	if (opts.find) {
		const passages = findPassages(page.content, opts.find, { context: 300, max: 20 });
		let body = passages.length
			? passages.map((p) => `[L${p.line} · char ${num(p.index)}]\n${p.excerpt}`).join("\n\n")
			: `No matches. Try a different term, or read the page with offset/maxChars.`;
		if (body.length > opts.maxChars) body = `${body.slice(0, opts.maxChars)}…\n\n[find output truncated to maxChars=${num(opts.maxChars)}; narrow the pattern or raise maxChars]`;
		const title = `Found ${passages.length}${passages.length === 20 ? "+" : ""} match${passages.length === 1 ? "" : "es"} for "${opts.find}"${passages.length ? " (offsets can be used with `offset` to read around a match)" : ""}:`;
		return { text: `${header.join("\n")}\n\n${title}\n\n${body}`, detail: { ...base, matches: passages.length, shown: body.length } };
	}

	const slice = sliceContent(page.content, opts.offset, opts.maxChars);
	const range: string[] = [];
	if (slice.offset > 0 || slice.truncated) {
		range.push(
			`Showing chars ${num(slice.offset)}–${num(slice.end)} of ${num(slice.total)}.${slice.truncated ? ` Continue with offset=${slice.end}${opts.maxChars < slice.total ? ` (or raise maxChars, or use find="…" to jump to a section)` : ""}.` : " (end of document)"}`,
		);
	}
	if (slice.offset >= slice.total && slice.total > 0) range.push("Offset is past the end of the document.");
	const text = `${header.join("\n")}${range.length ? `\n${range.join("\n")}` : ""}\n\n${slice.text}`;
	return { text, detail: { ...base, shown: slice.end - slice.offset, truncated: slice.truncated } };
}

function registerWebFetch(pi: ExtensionAPI) {
	pi.registerTool(
		defineTool<typeof fetchParams, FetchDetails>({
			name: "web_fetch",
			label: "Web Fetch",
			description:
				"Fetch one or more URLs and return readable content as markdown (HTML pages with boilerplate removed), raw text/JSON, or PDF text (via pdftotext when installed). GitHub URLs are resolved smartly: blob → raw file, repo → README, tree → directory listing, issues/PRs → full thread. Long documents are paged: use `offset` to continue (served from cache) or `find` to jump to matching passages. Private/loopback addresses are blocked by default.",
			promptSnippet: "Fetch URLs as readable markdown/text/JSON/PDF text; page long docs with offset, jump to passages with find; GitHub-aware.",
			promptGuidelines: [
				"Use web_fetch to read documentation, articles, API responses, GitHub files/issues, or PDFs from a URL; use `find` to locate a section and `offset` to page rather than re-fetching.",
			],
			parameters: fetchParams,

			async execute(_toolCallId, params, signal, onUpdate) {
				const config = loadConfig();
				const urls = toList(params.url, params.urls, MAX_URLS);
				if (urls.length === 0) throw new Error("No URL provided. Pass `url` or `urls`.");
				const mode = (params.mode ?? "readable") as FetchMode;
				const offset = params.offset ?? 0;
				const find = params.find?.trim() || undefined;
				const perUrlBudget = Math.max(200, Math.min(params.maxChars ?? config.maxChars, Math.floor((OUTPUT_BUDGET - 600 * urls.length) / urls.length)));
				const startedAt = Date.now();
				const limit = createLimiter(config.concurrency);
				const details: FetchDetails = { phase: "fetching", progress: 0, results: [], urlCount: urls.length, successful: 0, durationMs: 0, mode, find };
				let completed = 0;

				onUpdate?.({ content: [{ type: "text", text: `Fetching ${urls.length} URL${urls.length === 1 ? "" : "s"}…` }], details: { ...details, current: urls[0] } });

				const pages = await Promise.all(
					urls.map((u) =>
						limit(async (): Promise<FetchedContent> => {
							let page: FetchedContent;
							try {
								page = await fetchContent(u, { mode, signal, config, noCache: params.refresh });
							} catch (err) {
								// fetchContent never throws by contract; keep one bad URL from sinking its siblings anyway.
								if (signal?.aborted) throw err;
								page = { url: u, finalUrl: u, title: "", content: "", kind: "error", contentType: "", status: 0, bytes: 0, durationMs: 0, redirects: 0, cached: false, error: err instanceof Error ? err.message : String(err) };
							}
							completed++;
							onUpdate?.({ content: [{ type: "text", text: `Fetched ${completed}/${urls.length}…` }], details: { ...details, progress: completed / urls.length, current: u } });
							return page;
						}),
					),
				);

				const sections: string[] = [];
				for (const page of pages) {
					const { text, detail } = renderFetchedPage(page, { offset, maxChars: perUrlBudget, find, showTitle: true });
					details.results.push(detail);
					if (!detail.error) details.successful++;
					sections.push(text);
				}
				details.durationMs = Date.now() - startedAt;
				details.phase = "done";
				details.progress = 1;

				if (details.successful === 0) {
					const reasons = details.results.map((r) => `${r.url}: ${r.error}`).join("\n");
					throw new Error(urls.length === 1 ? (details.results[0]?.error ?? "Fetch failed") : `All ${urls.length} fetches failed:\n${reasons}`);
				}

				let text = sections.join("\n\n---\n\n");
				if (urls.length > 1) {
					text = `Fetched ${details.successful}/${urls.length} URLs in ${seconds(details.durationMs)}.\n\n${text}`;
				}
				const bounded = boundOutput(text, "Use offset/maxChars or find to read specific parts.");
				details.outputTruncated = bounded.truncated;
				return { content: [{ type: "text", text: bounded.text }], details };
			},

			renderCall(args, theme) {
				const urls = toList(args.url, args.urls, MAX_URLS);
				const head = theme.fg("toolTitle", theme.bold("web_fetch "));
				if (urls.length === 0) return new Text(head + theme.fg("error", "(no URL)"), 0, 0);
				const opts: string[] = [];
				if (args.mode && args.mode !== "readable") opts.push(`mode=${args.mode}`);
				if (args.offset) opts.push(`offset=${num(args.offset)}`);
				if (args.maxChars) opts.push(`maxChars=${num(args.maxChars)}`);
				if (args.find) opts.push(`find="${clip(args.find, 30)}"`);
				if (args.refresh) opts.push("refresh");
				const suffix = opts.length ? theme.fg("dim", `  (${opts.join(" · ")})`) : "";
				if (urls.length === 1) return new Text(head + theme.fg("accent", clip(urls[0]!, 90)) + suffix, 0, 0);
				const lines = [head + theme.fg("accent", `${urls.length} URLs`) + suffix];
				for (const u of urls.slice(0, 6)) lines.push(theme.fg("muted", `  ${clip(u, 88)}`));
				if (urls.length > 6) lines.push(theme.fg("dim", `  … ${urls.length - 6} more`));
				return new Text(lines.join("\n"), 0, 0);
			},

			renderResult(result, { expanded, isPartial }, theme, context) {
				const details = result.details as FetchDetails | undefined;
				if (isPartial) {
					const p = details?.progress ?? 0;
					const current = details?.current ? theme.fg("dim", ` ${clip(details.current, 60)}`) : "";
					return new Text(theme.fg("accent", `[${progressBar(p)}] fetching`) + current, 0, 0);
				}
				if (context.isError || !details) {
					const msg = result.content.find((c) => c.type === "text")?.text ?? "Error";
					return new Text(theme.fg("error", msg), 0, 0);
				}
				const textContent = result.content.find((c) => c.type === "text")?.text ?? "";

				const describe = (r: FetchResultDetail): string => {
					if (r.error) return theme.fg("error", `✗ ${clip(r.url, 70)}`) + theme.fg("dim", ` — ${clip(r.error, 90)}`);
					let s = theme.fg("success", clip(r.title || domainOf(r.finalUrl), 70));
					const meta: string[] = [];
					if (typeof r.matches === "number") meta.push(`${r.matches} match${r.matches === 1 ? "" : "es"} for "${clip(details.find ?? "", 24)}"`);
					else meta.push(r.truncated || r.offset ? `${num(r.offset)}–${num(r.offset + r.shown)} of ${num(r.chars)} chars` : `${num(r.chars)} chars`);
					meta.push(r.contentType || r.kind);
					meta.push(`${seconds(r.durationMs)}${r.cached ? " cached" : ""}`);
					s += theme.fg("muted", ` (${meta.join(" · ")})`);
					if (r.truncated) s += theme.fg("warning", " [more]");
					if (r.rewrittenFrom) s += theme.fg("dim", " ↪ resolved");
					if (r.warning) s += theme.fg("warning", " ⚠");
					return s;
				};

				if (details.results.length === 1) {
					const r = details.results[0]!;
					const lines = [describe(r)];
					if (r.finalUrl && r.finalUrl !== r.url) lines.push(theme.fg("dim", `  → ${clip(r.finalUrl, 100)}`));
					if (r.warning) lines.push(theme.fg("warning", `  ${clip(r.warning, 120)}`));
					if (details.outputTruncated) lines.push(theme.fg("warning", "  output truncated to fit tool limit"));
					const body = textContent.split("\n\n").slice(1).join("\n\n").trim();
					const preview = clip(body, expanded ? 1200 : 220);
					if (preview) lines.push(theme.fg("dim", preview));
					return new Text(lines.join("\n"), 0, 0);
				}

				const color = details.successful === details.urlCount ? "success" : details.successful > 0 ? "warning" : "error";
				const lines = [theme.fg(color, `${details.successful}/${details.urlCount} URLs`) + theme.fg("muted", ` · ${seconds(details.durationMs)}${details.outputTruncated ? " · output truncated" : ""}`)];
				for (const r of details.results.slice(0, expanded ? details.results.length : 6)) lines.push(`  ${describe(r)}`);
				if (!expanded && details.results.length > 6) lines.push(theme.fg("dim", `  … ${details.results.length - 6} more (ctrl+o to expand)`));
				return new Text(lines.join("\n"), 0, 0);
			},
		}),
	);
}

// ---------------------------------------------------------------------------
// /web command
// ---------------------------------------------------------------------------

function statusLines(): string[] {
	const config = loadConfig();
	const chain = resolveProviderChain(undefined, config);
	const cache = cacheStats();
	const lines = [
		`pi-web status`,
		`  config: ${config.configPath}${config.configFileFound ? "" : " (not found — using defaults)"}`,
		`  search provider: ${config.provider}${config.provider === "auto" ? ` → ${chain.join(" → ")}` : ""}`,
		`  brave: ${config.braveApiKey ? `key ${maskSecret(config.braveApiKey)}` : "not configured (BRAVE_API_KEY / braveApiKey)"}`,
		`  searxng: ${config.searxngUrl ?? "not configured (SEARXNG_URL / searxngUrl)"}`,
		`  duckduckgo: keyless (fast; may bot-check on bursts)`,
		`  exa: keyless MCP endpoint (semantic; ~3 concurrent)`,
		`  private network: ${config.allowPrivateNetwork ? "ALLOWED" : "blocked"} · timeout ${config.timeoutMs}ms · maxChars ${num(config.maxChars)} · concurrency ${config.concurrency}`,
		`  cache: ${cache.entries} pages, ${formatBytes(cache.bytes)} (15 min TTL) — /web clear to empty`,
		`  github token: ${process.env.GITHUB_TOKEN || process.env.GH_TOKEN ? "found (higher API rate limit)" : "none (60 req/h unauthenticated)"}`,
	];
	if (config.warnings.length) lines.push(`  warnings:`, ...config.warnings.map((w) => `    - ${w}`));
	return lines;
}

function registerCommand(pi: ExtensionAPI) {
	pi.registerCommand("web", {
		description: "pi-web: show search/fetch status, or `clear` the page cache",
		getArgumentCompletions: (prefix) => ["status", "clear"].filter((c) => c.startsWith(prefix)).map((c) => ({ value: c, label: c })),
		handler: async (args, ctx: ExtensionContext) => {
			const sub = args.trim().toLowerCase();
			if (sub === "clear") {
				const before = cacheStats();
				cacheClear();
				ctx.ui.notify(`pi-web: cleared ${before.entries} cached page${before.entries === 1 ? "" : "s"} (${formatBytes(before.bytes)})`, "info");
				return;
			}
			ctx.ui.notify(statusLines().join("\n"), "info");
		},
	});
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

export default function (pi: ExtensionAPI) {
	registerWebSearch(pi);
	registerWebFetch(pi);
	registerCommand(pi);

	pi.on("session_start", async (_event, ctx) => {
		const config = loadConfig();
		if (config.warnings.length && ctx.hasUI) {
			ctx.ui.notify(`pi-web config warnings:\n${config.warnings.map((w) => `- ${w}`).join("\n")}`, "warning");
		}
	});

	pi.on("session_shutdown", async () => {
		cacheClear();
	});
}
