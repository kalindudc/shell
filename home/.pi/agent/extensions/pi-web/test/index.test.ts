/**
 * Integration test: loads the extension entry point with a fake ExtensionAPI,
 * then exercises tool execution and TUI renderers without an LLM.
 *
 * Requires the pi runtime for peer imports:
 *   node --import ./test/_pi-resolve.mjs --test test/index.test.ts
 */

import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import { type TestServer, html, startServer } from "./_server.ts";

type AnyTool = {
	name: string;
	label: string;
	description: string;
	promptSnippet?: string;
	promptGuidelines?: string[];
	parameters: { properties: Record<string, unknown>; required?: string[] };
	execute: (id: string, params: unknown, signal: AbortSignal | undefined, onUpdate: ((u: unknown) => void) | undefined, ctx: unknown) => Promise<{ content: Array<{ type: string; text?: string }>; details: unknown }>;
	renderCall: (args: unknown, theme: unknown, context: unknown) => { render: (w: number) => string[] };
	renderResult: (result: unknown, opts: { expanded: boolean; isPartial: boolean }, theme: unknown, context: unknown) => { render: (w: number) => string[] };
};

const tools = new Map<string, AnyTool>();
const commands = new Map<string, { description?: string; handler: (args: string, ctx: unknown) => Promise<void> }>();
const handlers = new Map<string, Array<(event: unknown, ctx: unknown) => Promise<unknown>>>();

const fakePi = {
	registerTool: (t: AnyTool) => tools.set(t.name, t),
	registerCommand: (name: string, opts: { description?: string; handler: (args: string, ctx: unknown) => Promise<void> }) => commands.set(name, opts),
	on: (event: string, handler: (event: unknown, ctx: unknown) => Promise<unknown>) => {
		handlers.set(event, [...(handlers.get(event) ?? []), handler]);
	},
};

const theme = {
	fg: (_color: string, text: string) => text,
	bold: (text: string) => text,
	italic: (text: string) => text,
	strikethrough: (text: string) => text,
};
const renderContext = { args: {}, state: {}, isError: false, expanded: false, isPartial: false, invalidate() {} };

const notifications: Array<{ message: string; type?: string }> = [];
const fakeCtx = {
	hasUI: true,
	ui: { notify: (message: string, type?: string) => notifications.push({ message, type }) },
};

/** TUI components pad each line to the render width; trim for assertions. */
const renderText = (component: { render: (w: number) => string[] }) => component.render(120).map((l) => l.trimEnd()).join("\n");

let server: TestServer;

before(async () => {
	process.env.PI_WEB_ALLOW_PRIVATE = "1";
	process.env.PI_WEB_CONFIG = "/nonexistent/pi-web.json";
	const mod = await import("../index.ts");
	mod.default(fakePi as never);
	server = await startServer({
		"/doc": (_req, res) => html(res, `<html><head><title>Local Doc</title></head><body><main><h1>Local Doc</h1>${Array.from({ length: 61 }, (_, i) => `<p>Paragraph ${i + 1} with content.</p>`).join("")}<pre><code>code()</code></pre></main></body></html>`),
		"/json": (_req, res) => { res.writeHead(200, { "content-type": "application/json" }); res.end('{"ok":true}'); },
		"/missing": (_req, res) => html(res, "<title>Gone</title>", 404),
	});
});
after(() => server.close());

describe("registration", () => {
	it("registers web_search and web_fetch with prompt metadata", () => {
		assert.deepEqual([...tools.keys()].sort(), ["web_fetch", "web_search"]);
		for (const t of tools.values()) {
			assert.ok(t.label && t.description.length > 50, t.name);
			assert.ok(t.promptSnippet, `${t.name} promptSnippet`);
			assert.ok(t.promptGuidelines?.every((g) => g.includes(t.name)), `${t.name} guidelines must name the tool`);
		}
		assert.deepEqual(Object.keys(tools.get("web_search")!.parameters.properties).sort(), ["domains", "includeContent", "numResults", "provider", "queries", "query", "recency"]);
		assert.deepEqual(Object.keys(tools.get("web_fetch")!.parameters.properties).sort(), ["find", "maxChars", "mode", "offset", "refresh", "url", "urls"]);
	});
	it("registers the /web command and session hooks", () => {
		assert.ok(commands.has("web"));
		assert.ok(handlers.has("session_start"));
		assert.ok(handlers.has("session_shutdown"));
	});
	it("uses Google-compatible string enums (no anyOf) for enum parameters", () => {
		const props = tools.get("web_search")!.parameters.properties as Record<string, { anyOf?: unknown; enum?: unknown; type?: string }>;
		assert.equal(props.recency?.anyOf, undefined);
		assert.deepEqual(props.recency?.enum, ["day", "week", "month", "year"]);
		assert.deepEqual(props.provider?.enum, ["auto", "duckduckgo", "exa", "brave", "searxng"]);
	});
});

describe("web_fetch execute", () => {
	it("fetches a page, streams progress and returns informative headers + details", async () => {
		const tool = tools.get("web_fetch")!;
		const updates: unknown[] = [];
		const result = await tool.execute("call-1", { url: `${server.url}/doc` }, undefined, (u) => updates.push(u), {});
		const text = result.content[0]?.text ?? "";
		assert.ok(updates.length >= 2, "progress updates emitted");
		assert.match(text, /^# Local Doc\nSource: http:\/\/127\.0\.0\.1:\d+\/doc \(HTTP 200 · text\/html · [\d,]+ chars · [\d.]+s · content: <main>\)\n\n# Local Doc\n\nParagraph 1 with content\./);
		assert.match(text, /```\ncode\(\)\n```$/);
		const details = result.details as { results: Array<{ title: string; kind: string; truncated: boolean; cached: boolean }>; successful: number; urlCount: number };
		assert.equal(details.successful, 1);
		assert.equal(details.results[0]?.title, "Local Doc");
		assert.equal(details.results[0]?.kind, "html");
		assert.equal(details.results[0]?.truncated, false);
	});
	it("pages with offset from cache and reports the range", async () => {
		const tool = tools.get("web_fetch")!;
		const result = await tool.execute("call-2", { url: `${server.url}/doc`, maxChars: 300, offset: 0 }, undefined, undefined, {});
		const text = result.content[0]?.text ?? "";
		assert.match(text, /Showing chars 0–\d+ of [\d,]+\. Continue with offset=\d+/);
		const details = result.details as { results: Array<{ truncated: boolean; cached: boolean; shown: number }> };
		assert.equal(details.results[0]?.truncated, true);
		assert.equal(details.results[0]?.cached, true);
		assert.ok(details.results[0]!.shown <= 300);
	});
	it("returns matching passages with find", async () => {
		const tool = tools.get("web_fetch")!;
		const result = await tool.execute("call-3", { url: `${server.url}/doc`, find: "paragraph 42" }, undefined, undefined, {});
		const text = result.content[0]?.text ?? "";
		assert.match(text, /Found 1 match for "paragraph 42"/);
		assert.match(text, /\[L\d+ · char [\d,]+\]\n[\s\S]*Paragraph 42 with content/);
		assert.equal((result.details as { results: Array<{ matches: number }> }).results[0]?.matches, 1);
	});
	it("handles multiple URLs with partial failure without throwing", async () => {
		const tool = tools.get("web_fetch")!;
		const result = await tool.execute("call-4", { urls: [`${server.url}/json`, `${server.url}/missing`] }, undefined, undefined, {});
		const text = result.content[0]?.text ?? "";
		assert.match(text, /^Fetched 1\/2 URLs in [\d.]+s\./);
		assert.match(text, /"ok": true/);
		assert.match(text, /Error: HTTP 404 Not Found — "Gone" The page does not exist/);
	});
	it("keeps sibling results when one URL has a malformed escape or unsupported scheme (review F3)", async () => {
		const tool = tools.get("web_fetch")!;
		const result = await tool.execute("call-4b", { urls: [`${server.url}/json`, "https://github.com/o/r/tree/%ZZ/src", "mailto:x@y.z"] }, undefined, undefined, {});
		const text = result.content[0]?.text ?? "";
		assert.match(text, /^Fetched 1\/3 URLs/);
		assert.match(text, /"ok": true/);
		assert.match(text, /mailto:x@y.z\nError: Unsupported URL scheme/);
		const details = result.details as { results: Array<{ url: string; error?: string }> };
		assert.equal(details.results.length, 3);
		assert.ok(details.results[1]?.error, "tree URL with bad escape yields a per-URL error, not a throw");
	});
	it("bounds find output by maxChars", async () => {
		const tool = tools.get("web_fetch")!;
		const result = await tool.execute("call-4c", { url: `${server.url}/doc`, find: "/^Paragraph/", maxChars: 400 }, undefined, undefined, {});
		const text = result.content[0]?.text ?? "";
		assert.match(text, /Found \d+ matches for "\/\^Paragraph\/"/);
		assert.match(text, /\[find output truncated to maxChars=400/);
		const body = text.split("\n\n").slice(2).join("\n\n");
		assert.ok(body.length < 400 + 120, `find body bounded (${body.length} chars)`);
	});
	it("throws (isError) when every URL fails or no URL is given", async () => {
		const tool = tools.get("web_fetch")!;
		await assert.rejects(tool.execute("call-5", { url: `${server.url}/missing` }, undefined, undefined, {}), /HTTP 404/);
		await assert.rejects(tool.execute("call-6", {}, undefined, undefined, {}), /No URL provided/);
	});
	it("rejects unconfigured explicit search providers with guidance", async () => {
		const tool = tools.get("web_search")!;
		await assert.rejects(tool.execute("call-7", { query: "x", provider: "brave" }, undefined, undefined, {}), /Brave is not configured/);
		await assert.rejects(tool.execute("call-8", {}, undefined, undefined, {}), /No query provided/);
	});
});

describe("renderers", () => {
	it("web_search renderCall shows query and options", () => {
		const tool = tools.get("web_search")!;
		assert.equal(renderText(tool.renderCall({ query: "rust async" }, theme, renderContext)), 'web_search "rust async"');
		const multi = renderText(tool.renderCall({ queries: ["a", "b"], numResults: 10, recency: "week", includeContent: true }, theme, renderContext));
		assert.match(multi, /^web_search 2 queries  \(n=10 · recency=week · \+content\)\n  "a"\n  "b"$/);
		assert.equal(renderText(tool.renderCall({}, theme, renderContext)), "web_search (no query)");
	});
	it("web_search renderResult handles partial, error, collapsed and expanded states", () => {
		const tool = tools.get("web_search")!;
		const partial = renderText(tool.renderResult({ content: [], details: { phase: "searching", progress: 0.5, current: "q", queries: [], totalResults: 0, durationMs: 0 } }, { expanded: false, isPartial: true }, theme, renderContext));
		assert.match(partial, /^\[█████░░░░░\] searching q$/);
		const err = renderText(tool.renderResult({ content: [{ type: "text", text: "Search failed: boom" }], details: undefined }, { expanded: false, isPartial: false }, theme, { ...renderContext, isError: true }));
		assert.equal(err, "Search failed: boom");
		const details = {
			phase: "done",
			queries: [
				{ query: "q1", provider: "duckduckgo", results: [{ title: "T1", url: "https://a.example/x", snippet: "s1" }], rawCount: 1, durationMs: 800, attempts: [] },
				{ query: "q2", provider: null, results: [], rawCount: 0, durationMs: 100, error: "blocked", attempts: [] },
			],
			totalResults: 1,
			durationMs: 900,
		};
		const collapsed = renderText(tool.renderResult({ content: [], details }, { expanded: false, isPartial: false }, theme, renderContext));
		assert.match(collapsed, /1 results · 2 queries · duckduckgo · 0\.9s · 1 failed/);
		assert.match(collapsed, /▸ T1 · a\.example/);
		assert.match(collapsed, /✗ "q2": blocked/);
		const expanded = renderText(tool.renderResult({ content: [], details }, { expanded: true, isPartial: false }, theme, renderContext));
		assert.match(expanded, /"q1" \(duckduckgo · 0\.8s\)\n  1\. T1 · a\.example\n     https:\/\/a\.example\/x\n     s1/);
	});
	it("web_fetch renderCall and renderResult summarize the fetch", () => {
		const tool = tools.get("web_fetch")!;
		assert.equal(renderText(tool.renderCall({ url: "https://x.y/p", offset: 3000, find: "needle" }, theme, renderContext)), 'web_fetch https://x.y/p  (offset=3,000 · find="needle")');
		const details = {
			phase: "done",
			results: [{ url: "https://x.y/p", finalUrl: "https://x.y/p", title: "Title", kind: "html", status: 200, contentType: "text/html", chars: 5000, shown: 3000, offset: 0, truncated: true, durationMs: 300, cached: false, redirects: 0 }],
			urlCount: 1,
			successful: 1,
			durationMs: 300,
			mode: "readable",
		};
		const out = renderText(tool.renderResult({ content: [{ type: "text", text: "# Title\nSource: x\n\nBody preview text" }], details }, { expanded: false, isPartial: false }, theme, renderContext));
		assert.match(out, /^Title \(0–3,000 of 5,000 chars · text\/html · 0\.3s\) \[more\]\nBody preview text$/);
		const multi = renderText(tool.renderResult({ content: [{ type: "text", text: "" }], details: { ...details, urlCount: 2, successful: 1, results: [...details.results, { ...details.results[0], url: "https://z/", error: "HTTP 404" }] } }, { expanded: true, isPartial: false }, theme, renderContext));
		assert.match(multi, /^1\/2 URLs · 0\.3s\n  Title .*\n  ✗ https:\/\/z\/ — HTTP 404$/);
	});
});

describe("/web command", () => {
	it("reports status and clears the cache", async () => {
		const cmd = commands.get("web")!;
		await cmd.handler("", fakeCtx);
		assert.match(notifications.at(-1)?.message ?? "", /pi-web status[\s\S]*search provider: auto → duckduckgo → exa[\s\S]*private network: ALLOWED[\s\S]*cache: \d+ pages/);
		await cmd.handler("clear", fakeCtx);
		assert.match(notifications.at(-1)?.message ?? "", /cleared \d+ cached pages?/);
	});
	it("session_start surfaces config warnings only when present", async () => {
		notifications.length = 0;
		for (const h of handlers.get("session_start") ?? []) await h({}, fakeCtx);
		assert.equal(notifications.length, 0);
		process.env.PI_WEB_TIMEOUT_MS = "not-a-number";
		for (const h of handlers.get("session_start") ?? []) await h({}, fakeCtx);
		assert.match(notifications.at(-1)?.message ?? "", /PI_WEB_TIMEOUT_MS: expected a positive number/);
		delete process.env.PI_WEB_TIMEOUT_MS;
	});
});
