/**
 * URL → readable content pipeline.
 *
 *   normalize → GitHub rewrites → SSRF-guarded fetch → dispatch by content type
 *     html      → markdown (main-content selection)
 *     json      → pretty-printed text
 *     text/*    → as-is
 *     pdf       → text via `pdftotext` when installed (poppler); no npm deps
 *
 * Results are cached in memory (per process) so paging with `offset` and
 * `find` never re-downloads the page.
 */

import { spawn } from "node:child_process";
import type { PiWebConfig } from "./config.ts";
import { extractDocument, quickTitle } from "./html.ts";
import { NetError, decodeText, formatBytes, mimeType, readBodyLimited, safeFetch } from "./net.ts";

export type FetchMode = "readable" | "raw";
export type ContentKind = "html" | "markdown" | "text" | "json" | "pdf" | "github-api" | "error";

export interface FetchedContent {
	/** URL as requested (after normalization). */
	url: string;
	/** URL actually fetched after rewrites and redirects. */
	finalUrl: string;
	title: string;
	/** Full extracted content. */
	content: string;
	kind: ContentKind;
	contentType: string;
	status: number;
	bytes: number;
	durationMs: number;
	redirects: number;
	cached: boolean;
	description?: string;
	/** Which HTML root was used ("main", "article", "body", ...). */
	contentRoot?: string;
	/** Original URL when a rewrite happened (e.g. GitHub blob → raw). */
	rewrittenFrom?: string;
	warning?: string;
	error?: string;
}

export interface FetchOptions {
	mode: FetchMode;
	signal?: AbortSignal;
	config: PiWebConfig;
	/** Bypass and refresh the cache. */
	noCache?: boolean;
}

// ---------------------------------------------------------------------------
// URL normalization & rewrites
// ---------------------------------------------------------------------------

/**
 * Normalize user/model-supplied URLs: trim, strip <>, add https:// when the
 * scheme is missing, drop the fragment. A leading `name:` is only treated as a
 * scheme when it is not followed by a port number, so `example.com:8080/x`
 * and `localhost:3000` get `https://` prepended instead of being rejected.
 */
export function normalizeUrl(input: string): string {
	let raw = input.trim().replace(/^<|>$/g, "");
	if (!/^[a-z][a-z0-9+.-]*:\/\//i.test(raw)) {
		if (/^[a-z][a-z0-9+.-]*:(?!\d+(?:[/?#]|$))/i.test(raw)) {
			throw new NetError(`Unsupported URL scheme in "${input}" (only http/https are allowed)`, "blocked");
		}
		raw = `https://${raw}`;
	}
	const url = new URL(raw);
	if (url.protocol !== "http:" && url.protocol !== "https:") {
		throw new NetError(`Unsupported URL scheme "${url.protocol}" in "${input}" (only http/https are allowed)`, "blocked");
	}
	url.hash = "";
	return url.href;
}

/** First path segments on github.com that are not user/org names. */
const GITHUB_RESERVED = new Set([
	"about", "apps", "codespaces", "collections", "customer-stories", "enterprise", "events", "explore", "features", "issues",
	"login", "marketplace", "new", "notifications", "organizations", "orgs", "pricing", "pulls", "search", "security",
	"settings", "site", "sponsors", "team", "topics", "trending", "users",
]);

export interface Rewrite {
	url: string;
	kind: "github-raw" | "github-readme" | "github-tree" | "github-issue" | "none";
	/** Fallback URL (usually the original HTML page) if the rewritten target fails. */
	fallback?: string;
	meta?: Record<string, string>;
}

/** Rewrite well-known URL shapes into lighter, text-first equivalents. */
export function rewriteUrl(href: string): Rewrite {
	let url: URL;
	try {
		url = new URL(href);
	} catch {
		return { url: href, kind: "none" };
	}
	const host = url.hostname.toLowerCase().replace(/^www\./, "");
	if (host !== "github.com") return { url: href, kind: "none" };

	// Segments are already percent-encoded by the URL parser; pass them through untouched.
	const parts = url.pathname.split("/").filter(Boolean);
	const [owner, repo, section, ...rest] = parts;
	if (!owner || !repo || owner.startsWith("-") || GITHUB_RESERVED.has(owner.toLowerCase())) return { url: href, kind: "none" };
	const encode = (s: string) => s;

	if (parts.length === 2) {
		return {
			url: `https://raw.githubusercontent.com/${owner}/${repo}/HEAD/README.md`,
			kind: "github-readme",
			fallback: href,
			meta: { owner, repo },
		};
	}
	if ((section === "blob" || section === "raw") && rest.length >= 2) {
		const [ref, ...path] = rest;
		return {
			url: `https://raw.githubusercontent.com/${owner}/${repo}/${ref}/${encode(path.join("/"))}`,
			kind: "github-raw",
			fallback: href,
		};
	}
	if (section === "tree" && rest.length >= 1) {
		const [ref, ...path] = rest;
		const api = new URL(`https://api.github.com/repos/${owner}/${repo}/contents/${encode(path.join("/"))}`);
		api.searchParams.set("ref", safeDecode(ref!));
		return { url: api.href, kind: "github-tree", fallback: href, meta: { owner, repo, ref: safeDecode(ref!), path: safeDecode(path.join("/")) } };
	}
	if ((section === "issues" || section === "pull") && /^\d+$/.test(rest[0] ?? "")) {
		return {
			url: `https://api.github.com/repos/${owner}/${repo}/issues/${rest[0]}`,
			kind: "github-issue",
			fallback: href,
			meta: { owner, repo, number: rest[0]!, type: section },
		};
	}
	return { url: href, kind: "none" };
}

/** decodeURIComponent that tolerates malformed %-escapes (returns the input unchanged). */
function safeDecode(segment: string): string {
	try {
		return decodeURIComponent(segment);
	} catch {
		return segment;
	}
}

function githubHeaders(config: PiWebConfig): Record<string, string> {
	const headers: Record<string, string> = {
		"User-Agent": config.userAgent,
		Accept: "application/vnd.github+json",
		"X-GitHub-Api-Version": "2022-11-28",
	};
	const token = process.env.GITHUB_TOKEN ?? process.env.GH_TOKEN;
	if (token) headers.Authorization = `Bearer ${token}`;
	return headers;
}

// ---------------------------------------------------------------------------
// Cache
// ---------------------------------------------------------------------------

const CACHE_MAX_ENTRIES = 64;
const CACHE_MAX_BYTES = 48 * 1024 * 1024;
const CACHE_TTL_MS = 15 * 60 * 1000;

interface CacheEntry {
	value: FetchedContent;
	at: number;
	size: number;
}

const cache = new Map<string, CacheEntry>();
let cacheBytes = 0;

function cacheKey(url: string, mode: FetchMode): string {
	return `${mode}:${url}`;
}

export function cacheGet(url: string, mode: FetchMode): FetchedContent | undefined {
	const key = cacheKey(url, mode);
	const entry = cache.get(key);
	if (!entry) return undefined;
	if (Date.now() - entry.at > CACHE_TTL_MS) {
		cache.delete(key);
		cacheBytes -= entry.size;
		return undefined;
	}
	// LRU touch
	cache.delete(key);
	cache.set(key, entry);
	return entry.value;
}

export function cacheSet(url: string, mode: FetchMode, value: FetchedContent): void {
	if (value.error && !value.content) return;
	const key = cacheKey(url, mode);
	const size = value.content.length * 2 + 512;
	const existing = cache.get(key);
	if (existing) {
		cache.delete(key);
		cacheBytes -= existing.size;
	}
	cache.set(key, { value, at: Date.now(), size });
	cacheBytes += size;
	while (cache.size > CACHE_MAX_ENTRIES || cacheBytes > CACHE_MAX_BYTES) {
		const oldest = cache.keys().next().value;
		if (oldest === undefined) break;
		cacheBytes -= cache.get(oldest)?.size ?? 0;
		cache.delete(oldest);
	}
}

export function cacheStats(): { entries: number; bytes: number } {
	return { entries: cache.size, bytes: cacheBytes };
}

export function cacheClear(): void {
	cache.clear();
	cacheBytes = 0;
}

// ---------------------------------------------------------------------------
// Content helpers
// ---------------------------------------------------------------------------

function looksLikeText(bytes: Uint8Array): boolean {
	const sample = bytes.subarray(0, Math.min(bytes.length, 2048));
	let suspicious = 0;
	for (const b of sample) {
		if (b === 0) return false;
		if (b < 7 || (b > 14 && b < 32)) suspicious++;
	}
	return suspicious < sample.length * 0.05;
}

function looksLikeHtml(text: string): boolean {
	return /^\s*(?:<!doctype\s+html|<html[\s>]|<head[\s>]|<body[\s>])/i.test(text.slice(0, 1024));
}

function isPdf(bytes: Uint8Array, contentType: string, url: string): boolean {
	if (contentType === "application/pdf" || contentType === "application/x-pdf") return true;
	if (/\.pdf($|[?#])/i.test(url) && bytes.length > 4) {
		return bytes[0] === 0x25 && bytes[1] === 0x50 && bytes[2] === 0x44 && bytes[3] === 0x46; // %PDF
	}
	return false;
}

function titleFromText(text: string, url: string): string {
	const heading = /^#{1,2}\s+(.+)$/m.exec(text);
	if (heading?.[1]) return heading[1].replace(/[*_`]/g, "").trim();
	try {
		const { pathname, hostname } = new URL(url);
		const last = pathname.split("/").filter(Boolean).pop();
		return last ? safeDecode(last) : hostname;
	} catch {
		return url;
	}
}

function prettyJson(text: string): string {
	if (text.length > 512 * 1024 || text.includes("\n")) return text;
	try {
		return JSON.stringify(JSON.parse(text), null, 2);
	} catch {
		return text;
	}
}

export async function pdfToText(bytes: Uint8Array, signal?: AbortSignal, timeoutMs = 30_000): Promise<string> {
	return new Promise((resolve, reject) => {
		const child = spawn("pdftotext", ["-layout", "-enc", "UTF-8", "-", "-"], { stdio: ["pipe", "pipe", "pipe"] });
		const out: Buffer[] = [];
		const err: Buffer[] = [];
		const timer = setTimeout(() => child.kill("SIGKILL"), timeoutMs);
		const onAbort = () => child.kill("SIGKILL");
		signal?.addEventListener("abort", onAbort, { once: true });
		child.stdout.on("data", (d: Buffer) => out.push(d));
		child.stderr.on("data", (d: Buffer) => err.push(d));
		child.on("error", (e: NodeJS.ErrnoException) => {
			clearTimeout(timer);
			signal?.removeEventListener("abort", onAbort);
			if (e.code === "ENOENT") {
				reject(new Error("PDF extraction requires `pdftotext` (poppler). Install with `brew install poppler` or `apt install poppler-utils`."));
			} else reject(e);
		});
		child.on("close", (code) => {
			clearTimeout(timer);
			signal?.removeEventListener("abort", onAbort);
			if (signal?.aborted) return reject(new NetError("Request cancelled", "aborted"));
			if (code !== 0 && out.length === 0) {
				return reject(new Error(`pdftotext exited with code ${code}: ${Buffer.concat(err).toString("utf8").trim().slice(0, 300)}`));
			}
			resolve(Buffer.concat(out).toString("utf8").replace(/\f/g, "\n\n---\n\n").replace(/[ \t]+\n/g, "\n").trim());
		});
		child.stdin.on("error", () => {
			/* EPIPE when pdftotext is missing — handled by "error" above */
		});
		child.stdin.end(Buffer.from(bytes));
	});
}

// ---------------------------------------------------------------------------
// GitHub API formatters
// ---------------------------------------------------------------------------

interface GhContentEntry {
	name: string;
	path: string;
	type: "file" | "dir" | "symlink" | "submodule";
	size: number;
	html_url?: string;
}

function formatGithubTree(payload: unknown, meta: Record<string, string>): { title: string; content: string } {
	const entries = Array.isArray(payload) ? (payload as GhContentEntry[]) : [payload as GhContentEntry];
	const title = `${meta.owner}/${meta.repo}${meta.path ? `/${meta.path}` : ""} @ ${meta.ref}`;
	const sorted = [...entries].sort((a, b) => (a.type === b.type ? a.name.localeCompare(b.name) : a.type === "dir" ? -1 : 1));
	const lines = sorted.map((e) => {
		const icon = e.type === "dir" ? "📁" : e.type === "submodule" ? "🔗" : "📄";
		const size = e.type === "file" ? ` (${formatBytes(e.size)})` : "";
		const link = e.type === "dir"
			? `https://github.com/${meta.owner}/${meta.repo}/tree/${meta.ref}/${e.path}`
			: `https://github.com/${meta.owner}/${meta.repo}/blob/${meta.ref}/${e.path}`;
		return `- ${icon} [${e.name}](${link})${size}`;
	});
	return { title, content: `# ${title}\n\n${lines.join("\n")}\n\n_${entries.length} entries. Fetch a file with its blob URL to read it._` };
}

interface GhIssue {
	number: number;
	title: string;
	state: string;
	html_url: string;
	user?: { login: string };
	created_at: string;
	updated_at?: string;
	closed_at?: string | null;
	body?: string | null;
	comments: number;
	labels?: Array<{ name: string } | string>;
	pull_request?: { merged_at?: string | null; html_url?: string };
	merged_at?: string | null;
	draft?: boolean;
}
interface GhComment {
	user?: { login: string };
	created_at: string;
	body?: string | null;
}

function formatGithubIssue(issue: GhIssue, comments: GhComment[], meta: Record<string, string>): { title: string; content: string } {
	const type = issue.pull_request ? "Pull Request" : "Issue";
	const labels = (issue.labels ?? []).map((l) => (typeof l === "string" ? l : l.name)).filter(Boolean);
	const state = issue.pull_request?.merged_at ? "merged" : issue.state;
	const lines = [
		`# ${issue.title}`,
		"",
		`**${type} #${issue.number}** in ${meta.owner}/${meta.repo} · ${state}${issue.draft ? " (draft)" : ""} · by @${issue.user?.login ?? "unknown"} · opened ${issue.created_at.slice(0, 10)}${issue.closed_at ? ` · closed ${issue.closed_at.slice(0, 10)}` : ""}`,
	];
	if (labels.length) lines.push(`Labels: ${labels.join(", ")}`);
	lines.push(`URL: ${issue.html_url}`, "", issue.body?.trim() || "_(no description)_");
	if (comments.length) {
		lines.push("", "---", "", `## Comments (${comments.length}${issue.comments > comments.length ? ` of ${issue.comments}` : ""})`);
		for (const c of comments) {
			lines.push("", `### @${c.user?.login ?? "unknown"} · ${c.created_at.slice(0, 10)}`, "", c.body?.trim() || "_(empty)_");
		}
	}
	return { title: `${issue.title} · ${type} #${issue.number}`, content: lines.join("\n") };
}

// ---------------------------------------------------------------------------
// Main entry point
// ---------------------------------------------------------------------------

async function fetchGithubApi(rewrite: Rewrite, options: FetchOptions, startedAt: number, requestedUrl: string): Promise<FetchedContent | null> {
	const { config, signal } = options;
	const headers = githubHeaders(config);
	const { response, finalUrl, redirects } = await safeFetch(rewrite.url, {
		signal,
		timeoutMs: config.timeoutMs,
		maxBytes: config.maxResponseBytes,
		headers,
	});
	const bytes = await readBodyLimited(response, config.maxResponseBytes, signal);
	if (response.status === 403 || response.status === 429 || response.status === 404 || response.status === 401) {
		return null; // rate limited / private / missing → caller falls back to HTML
	}
	if (response.status !== 200) return null;
	const payload: unknown = JSON.parse(new TextDecoder().decode(bytes));
	const meta = rewrite.meta ?? {};
	let formatted: { title: string; content: string };
	if (rewrite.kind === "github-tree") {
		if (!Array.isArray(payload)) return null; // it's a file → let raw path handle it
		formatted = formatGithubTree(payload, meta);
	} else {
		const issue = payload as GhIssue;
		let comments: GhComment[] = [];
		if (issue.comments > 0) {
			try {
				const c = await safeFetch(`${rewrite.url}/comments?per_page=50`, { signal, timeoutMs: config.timeoutMs, maxBytes: config.maxResponseBytes, headers });
				if (c.response.status === 200) {
					comments = JSON.parse(new TextDecoder().decode(await readBodyLimited(c.response, config.maxResponseBytes, signal))) as GhComment[];
				} else await c.response.body?.cancel().catch(() => {});
			} catch {
				/* comments are best-effort */
			}
		}
		formatted = formatGithubIssue(issue, comments, meta);
	}
	return {
		url: requestedUrl,
		finalUrl,
		title: formatted.title,
		content: formatted.content,
		kind: "github-api",
		contentType: "application/json",
		status: response.status,
		bytes: bytes.byteLength,
		durationMs: Date.now() - startedAt,
		redirects,
		cached: false,
		rewrittenFrom: requestedUrl,
	};
}

export async function fetchContent(input: string, options: FetchOptions): Promise<FetchedContent> {
	const startedAt = Date.now();
	const { config, signal, mode } = options;
	let url: string;
	try {
		url = normalizeUrl(input);
	} catch (err) {
		return errorResult(input, input, err, startedAt);
	}

	if (!options.noCache) {
		const hit = cacheGet(url, mode);
		if (hit) return { ...hit, cached: true, durationMs: Date.now() - startedAt };
	}

	// Everything from here on runs inside the try so that any unexpected throw
	// becomes a per-URL error result rather than failing the whole tool call.
	let target = url;
	try {
		const rewrite = rewriteUrl(url);
		target = rewrite.url;
		let rewrittenFrom: string | undefined = rewrite.kind === "none" ? undefined : url;

		if (rewrite.kind === "github-tree" || rewrite.kind === "github-issue") {
			const viaApi = await fetchGithubApi(rewrite, options, startedAt, url);
			if (viaApi) {
				cacheSet(url, mode, viaApi);
				return viaApi;
			}
			target = rewrite.fallback ?? url;
			rewrittenFrom = undefined;
		}

		let result = await fetchAndExtract(url, target, options, startedAt);
		if (result.error && rewrite.fallback && target !== rewrite.fallback && (result.status === 404 || result.status === 0)) {
			// e.g. repo without README.md → fetch the HTML page instead
			result = await fetchAndExtract(url, rewrite.fallback, options, startedAt);
			rewrittenFrom = undefined;
		}
		result.rewrittenFrom = rewrittenFrom;
		cacheSet(url, mode, result);
		return result;
	} catch (err) {
		return errorResult(url, target, err, startedAt);
	}
}

function errorResult(url: string, finalUrl: string, err: unknown, startedAt: number): FetchedContent {
	const message = err instanceof Error ? err.message : String(err);
	return {
		url,
		finalUrl,
		title: "",
		content: "",
		kind: "error",
		contentType: "",
		status: 0,
		bytes: 0,
		durationMs: Date.now() - startedAt,
		redirects: 0,
		cached: false,
		error: message,
	};
}

async function fetchAndExtract(requestedUrl: string, target: string, options: FetchOptions, startedAt: number): Promise<FetchedContent> {
	const { config, signal, mode } = options;
	const { response, finalUrl, redirects } = await safeFetch(target, {
		signal,
		timeoutMs: config.timeoutMs,
		maxBytes: config.maxResponseBytes,
		allowPrivateNetwork: config.allowPrivateNetwork,
		headers: {
			"User-Agent": config.userAgent,
			Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,text/markdown;q=0.9,text/plain;q=0.8,application/json;q=0.8,application/pdf;q=0.7,*/*;q=0.5",
			"Accept-Language": "en-US,en;q=0.9",
			"Cache-Control": "no-cache",
		},
	});

	const contentTypeHeader = response.headers.get("content-type");
	const contentType = mimeType(contentTypeHeader);
	const bytes = await readBodyLimited(response, config.maxResponseBytes, signal);
	const base: Omit<FetchedContent, "title" | "content" | "kind"> = {
		url: requestedUrl,
		finalUrl,
		contentType,
		status: response.status,
		bytes: bytes.byteLength,
		durationMs: Date.now() - startedAt,
		redirects,
		cached: false,
	};

	// --- PDF ---------------------------------------------------------------
	if (isPdf(bytes, contentType, finalUrl)) {
		if (!response.ok) return { ...base, title: "", content: "", kind: "error", error: `HTTP ${response.status} ${response.statusText}`.trim() };
		const text = await pdfToText(bytes, signal);
		const pages = (text.match(/\n\n---\n\n/g)?.length ?? 0) + 1;
		return {
			...base,
			title: titleFromText(text, finalUrl),
			content: text,
			kind: "pdf",
			durationMs: Date.now() - startedAt,
			description: `PDF, ${pages} page${pages === 1 ? "" : "s"}, ${formatBytes(bytes.byteLength)}`,
		};
	}

	// --- Binary ------------------------------------------------------------
	const textual =
		contentType.startsWith("text/") ||
		/json|xml|javascript|ecmascript|yaml|toml|csv|x-sh|x-www-form|graphql|markdown|x-python|x-ruby|x-perl|x-httpd-php|x-ndjson/i.test(contentType) ||
		((contentType === "" || contentType === "application/octet-stream") && looksLikeText(bytes));
	if (!textual) {
		return {
			...base,
			title: "",
			content: "",
			kind: "error",
			error: `Unsupported binary content: ${contentType || "unknown type"} (${formatBytes(bytes.byteLength)}). Only HTML, text, JSON, XML, and PDF are supported.`,
		};
	}

	const text = decodeText(bytes, contentTypeHeader);
	const isHtml = contentType === "text/html" || contentType === "application/xhtml+xml" || ((contentType === "" || contentType === "application/octet-stream") && looksLikeHtml(text));

	// --- Error status ------------------------------------------------------
	if (!response.ok && mode !== "raw") {
		let hint = "";
		if (isHtml) {
			const title = quickTitle(text);
			hint = title ? ` — "${title}"` : "";
		}
		const guidance = response.status === 404
			? " The page does not exist; check the URL or search for the resource."
			: response.status === 403 || response.status === 401
				? " Access denied (login, paywall, or bot protection)."
				: response.status === 429
					? " Rate limited; retry later."
					: response.status >= 500
						? " Server error; retry later."
						: "";
		return { ...base, title: "", content: "", kind: "error", error: `HTTP ${response.status} ${response.statusText}`.trim() + hint + guidance };
	}

	// --- Raw mode ----------------------------------------------------------
	if (mode === "raw") {
		return { ...base, title: titleFromText(text, finalUrl), content: text, kind: isHtml ? "html" : contentType.includes("json") ? "json" : "text" };
	}

	// --- HTML --------------------------------------------------------------
	if (isHtml) {
		const doc = extractDocument(text, finalUrl);
		let warning: string | undefined;
		if (doc.markdown.length < 200) {
			warning = doc.likelyJsRendered
				? "Page appears to be JavaScript-rendered; little static content was available. Try the site's API, an alternate URL (docs/raw/print view), or a search for the same content."
				: "Very little readable text was extracted from this page.";
		}
		return {
			...base,
			title: doc.title || titleFromText(doc.markdown, finalUrl),
			content: doc.markdown,
			kind: "html",
			description: doc.description || undefined,
			contentRoot: doc.contentRoot,
			warning,
			durationMs: Date.now() - startedAt,
		};
	}

	// --- JSON / text -------------------------------------------------------
	if (contentType.includes("json") || /^\s*[[{]/.test(text.slice(0, 64)) && contentType === "") {
		return { ...base, title: titleFromText("", finalUrl), content: prettyJson(text), kind: "json" };
	}
	const isMarkdown = contentType.includes("markdown") || /\.(md|markdown|mdx)$/i.test(new URL(finalUrl).pathname);
	return { ...base, title: titleFromText(text, finalUrl), content: text.replace(/\r\n?/g, "\n"), kind: isMarkdown ? "markdown" : "text" };
}

// ---------------------------------------------------------------------------
// Paging and search within content
// ---------------------------------------------------------------------------

export interface ContentSlice {
	text: string;
	offset: number;
	end: number;
	total: number;
	truncated: boolean;
}

/** Slice content for output, preferring to cut at a line boundary. */
export function sliceContent(content: string, offset: number, maxChars: number): ContentSlice {
	const total = content.length;
	const start = Math.max(0, Math.min(offset, total));
	let end = Math.min(total, start + Math.max(1, maxChars));
	if (end < total) {
		const window = content.lastIndexOf("\n", end);
		if (window > start + maxChars * 0.7) end = window + 1;
	}
	return { text: content.slice(start, end), offset: start, end, total, truncated: end < total };
}

export interface Passage {
	/** Character offset of the match in the full content. */
	index: number;
	/** 1-based line number. */
	line: number;
	excerpt: string;
}

/**
 * Find passages matching `needle`.
 *
 * Plain text matches case-insensitively. `/pattern/flags` is a JS regex; the
 * `g` and `m` flags are always on (so `^`/`$` anchor to lines, which is what
 * you want in a document), add `i` yourself for case-insensitive regexes.
 */
export function findPassages(content: string, needle: string, options: { context?: number; max?: number } = {}): Passage[] {
	const context = options.context ?? 300;
	const max = options.max ?? 20;
	const literal = () => new RegExp(needle.trim().replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "gi");
	let re: RegExp;
	const m = /^\/(.+)\/([gimsuy]*)$/.exec(needle.trim());
	try {
		re = m ? new RegExp(m[1]!, [...new Set(`${m[2]}gm`)].join("")) : literal();
	} catch {
		re = literal();
	}
	const passages: Passage[] = [];
	let lastEnd = -1;
	let match: RegExpExecArray | null;
	while ((match = re.exec(content)) !== null && passages.length < max) {
		if (match[0] === "") {
			re.lastIndex++;
			continue;
		}
		const idx = match.index;
		if (idx < lastEnd) continue; // inside the previous excerpt
		const start = Math.max(0, idx - context);
		const end = Math.min(content.length, idx + match[0].length + context);
		const excerpt = `${start > 0 ? "…" : ""}${content.slice(start, end).trim()}${end < content.length ? "…" : ""}`;
		const line = content.slice(0, idx).split("\n").length;
		passages.push({ index: idx, line, excerpt });
		lastEnd = end;
	}
	return passages;
}
