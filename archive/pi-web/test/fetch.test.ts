import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import { CONFIG_DEFAULTS, type PiWebConfig } from "../config.ts";
import { cacheClear, cacheGet, cacheSet, cacheStats, fetchContent, findPassages, normalizeUrl, rewriteUrl, sliceContent } from "../fetch.ts";
import { type TestServer, html, startServer } from "./_server.ts";

function config(overrides: Partial<PiWebConfig> = {}): PiWebConfig {
	return { ...CONFIG_DEFAULTS, allowPrivateNetwork: true, configPath: "/dev/null", configFileFound: false, warnings: [], ...overrides };
}

describe("normalizeUrl", () => {
	it("adds https, strips fragments and angle brackets", () => {
		assert.equal(normalizeUrl(" example.com/a#frag "), "https://example.com/a");
		assert.equal(normalizeUrl("<https://example.com/>"), "https://example.com/");
		assert.equal(normalizeUrl("http://example.com/x?y=1"), "http://example.com/x?y=1");
	});
	it("rejects non-http schemes", () => {
		assert.throws(() => normalizeUrl("file:///etc/passwd"), /Unsupported URL scheme/);
		assert.throws(() => normalizeUrl("mailto:x@y.z"), /Unsupported URL scheme/);
		assert.throws(() => normalizeUrl("javascript:alert(1)"), /Unsupported URL scheme/);
	});
	it("treats scheme-less host:port as a host, not a scheme (review F4)", () => {
		assert.equal(normalizeUrl("example.com:8080/path"), "https://example.com:8080/path");
		assert.equal(normalizeUrl("docs.lan:8080/api?x=1"), "https://docs.lan:8080/api?x=1");
		assert.equal(normalizeUrl("localhost:3000"), "https://localhost:3000/");
		assert.equal(normalizeUrl("localhost:3000/x"), "https://localhost:3000/x");
		assert.equal(normalizeUrl("192.168.1.10:9000/"), "https://192.168.1.10:9000/");
	});
});

describe("rewriteUrl (GitHub)", () => {
	it("maps blob and raw paths to raw.githubusercontent.com", () => {
		const r = rewriteUrl("https://github.com/o/r/blob/main/dir/file name.md?plain=1");
		assert.equal(r.kind, "github-raw");
		assert.equal(r.url, "https://raw.githubusercontent.com/o/r/main/dir/file%20name.md");
		assert.equal(rewriteUrl("https://github.com/o/r/raw/v1.2/x.ts").url, "https://raw.githubusercontent.com/o/r/v1.2/x.ts");
	});
	it("maps repo roots to README with the HTML page as fallback", () => {
		const r = rewriteUrl("https://github.com/o/r/");
		assert.equal(r.kind, "github-readme");
		assert.equal(r.url, "https://raw.githubusercontent.com/o/r/HEAD/README.md");
		assert.equal(r.fallback, "https://github.com/o/r/");
	});
	it("maps tree and issue/pull URLs to the API", () => {
		const t = rewriteUrl("https://github.com/o/r/tree/main/src/lib");
		assert.equal(t.kind, "github-tree");
		assert.equal(t.url, "https://api.github.com/repos/o/r/contents/src/lib?ref=main");
		assert.equal(rewriteUrl("https://github.com/o/r/issues/12").url, "https://api.github.com/repos/o/r/issues/12");
		assert.equal(rewriteUrl("https://github.com/o/r/pull/7").kind, "github-issue");
	});
	it("tolerates malformed percent-escapes instead of throwing URIError (review F3)", () => {
		const a = rewriteUrl("https://github.com/o/r/tree/%ZZ/src");
		assert.equal(a.kind, "github-tree");
		assert.equal(a.meta?.ref, "%ZZ");
		const b = rewriteUrl("https://github.com/o/r/tree/main/%E0%A4%A");
		assert.equal(b.kind, "github-tree");
		assert.equal(b.meta?.path, "%E0%A4%A");
	});
	it("leaves other GitHub and non-GitHub URLs alone", () => {
		assert.equal(rewriteUrl("https://github.com/o/r/actions").kind, "none");
		assert.equal(rewriteUrl("https://github.com/orgs/x").kind, "none");
		assert.equal(rewriteUrl("https://example.com/o/r/blob/main/x").kind, "none");
		assert.equal(rewriteUrl("https://github.com/o/r/pull/abc").kind, "none");
	});
});

describe("sliceContent / findPassages", () => {
	const doc = Array.from({ length: 50 }, (_, i) => `Line ${i + 1}: ${i === 20 ? "the NEEDLE is here" : "filler text"}`).join("\n");

	it("slices at a line boundary and reports paging metadata", () => {
		const s = sliceContent(doc, 0, 100);
		assert.ok(s.text.endsWith("\n"));
		assert.ok(s.end <= 100 && s.end >= 70);
		assert.equal(s.truncated, true);
		assert.equal(s.total, doc.length);
		const tail = sliceContent(doc, s.end, 100_000);
		assert.equal(tail.truncated, false);
		assert.equal(s.text + tail.text, doc);
	});
	it("clamps offsets past the end", () => {
		const s = sliceContent(doc, 10_000, 10);
		assert.equal(s.text, "");
		assert.equal(s.offset, doc.length);
	});
	it("finds case-insensitive passages with line numbers and context", () => {
		const p = findPassages(doc, "needle", { context: 12, max: 5 });
		assert.equal(p.length, 1);
		assert.equal(p[0]?.line, 21);
		assert.match(p[0]?.excerpt ?? "", /^…[\s\S]*NEEDLE[\s\S]*…$/);
	});
	it("anchors ^/$ to lines in /regex/ needles (m is always on) and honours user flags", () => {
		const md = "# Title\n\n## Install\n\ntext\n\n## install notes\n\n## Usage\n";
		assert.equal(findPassages(md, "/^## Install/", { context: 0 }).length, 1);
		assert.equal(findPassages(md, "/^## install/i", { context: 0 }).length, 2);
		assert.equal(findPassages(md, "/^## /", { context: 0 }).length, 3);
		assert.equal(findPassages(md, "/^## /gm", { context: 0 }).length, 3, "duplicate flags are tolerated");
	});
	it("supports /regex/ needles, caps matches and merges overlapping windows", () => {
		const p = findPassages(doc, "/line \\d+/i", { context: 5, max: 3 });
		assert.equal(p.length, 3);
		const wide = findPassages(doc, "filler", { context: doc.length, max: 20 });
		assert.equal(wide.length, 1, "matches inside the previous excerpt are skipped");
		const narrow = findPassages(doc, "filler", { context: 0, max: 100 });
		assert.equal(narrow.length, 49, "non-overlapping matches are all reported");
	});
	it("falls back to literal matching for invalid regexes and empty patterns", () => {
		assert.equal(findPassages(doc, "/([/", {}).length, 0);
		assert.equal(findPassages("a(b", "a(b", {}).length, 1);
	});
});

describe("cache", () => {
	it("stores, touches and clears entries; skips empty errors", () => {
		cacheClear();
		const value = { url: "u", finalUrl: "u", title: "t", content: "c", kind: "text" as const, contentType: "text/plain", status: 200, bytes: 1, durationMs: 1, redirects: 0, cached: false };
		cacheSet("https://a/", "readable", value);
		assert.equal(cacheGet("https://a/", "readable")?.title, "t");
		assert.equal(cacheGet("https://a/", "raw"), undefined);
		cacheSet("https://b/", "readable", { ...value, content: "", error: "x", kind: "error" });
		assert.equal(cacheStats().entries, 1);
		cacheClear();
		assert.equal(cacheStats().entries, 0);
	});
});

describe("fetchContent (local server)", () => {
	let server: TestServer;
	let hits = 0;
	before(async () => {
		server = await startServer({
			"/page": (_req, res) => {
				hits++;
				html(res, `<html><head><title>Doc Title</title><meta name="description" content="A doc"></head><body><nav>Nav</nav><main><h1>Doc</h1><p>${"Paragraph text. ".repeat(30)}</p><pre><code class="language-js">let x = 1;</code></pre></main><footer>F</footer></body></html>`);
			},
			"/json": (_req, res) => { res.writeHead(200, { "content-type": "application/json" }); res.end('{"a":1,"b":[1,2]}'); },
			"/text": (_req, res) => { res.writeHead(200, { "content-type": "text/plain" }); res.end("# Heading\n\nplain"); },
			"/md": (_req, res) => { res.writeHead(200, { "content-type": "text/markdown" }); res.end("# Readme\n\nbody"); },
			"/octet-html": (_req, res) => { res.writeHead(200, { "content-type": "application/octet-stream" }); res.end("<!doctype html><html><head><title>Sniffed</title></head><body><p>" + "sniffed body ".repeat(40) + "</p></body></html>"); },
			"/binary": (_req, res) => { res.writeHead(200, { "content-type": "image/png" }); res.end(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 0])); },
			"/forbidden": (_req, res) => html(res, "<html><head><title>Login required</title></head><body>no</body></html>", 403),
			"/shell": (_req, res) => html(res, `<html><head><title>App</title><script src="1.js"></script><script src="2.js"></script><script src="3.js"></script></head><body><div id="root"></div></body></html>`),
			"/redirect": (_req, res) => { res.writeHead(302, { location: "/page" }); res.end(); },
		});
	});
	after(() => server.close());

	it("converts HTML to markdown with metadata, content root and timing", async () => {
		cacheClear();
		const r = await fetchContent(`${server.url}/page`, { mode: "readable", config: config() });
		assert.equal(r.error, undefined);
		assert.equal(r.kind, "html");
		assert.equal(r.title, "Doc Title");
		assert.equal(r.description, "A doc");
		assert.equal(r.contentRoot, "main");
		assert.equal(r.status, 200);
		assert.match(r.content, /^# Doc\n\nParagraph text\./);
		assert.match(r.content, /```js\nlet x = 1;\n```$/);
		assert.doesNotMatch(r.content, /Nav|F$/);
		assert.equal(r.cached, false);
		assert.ok(r.durationMs >= 0);
	});
	it("serves repeat requests from cache and bypasses it with noCache", async () => {
		const before = hits;
		const r = await fetchContent(`${server.url}/page#frag`, { mode: "readable", config: config() });
		assert.equal(r.cached, true);
		assert.equal(hits, before);
		const fresh = await fetchContent(`${server.url}/page`, { mode: "readable", config: config(), noCache: true });
		assert.equal(fresh.cached, false);
		assert.equal(hits, before + 1);
	});
	it("returns raw HTML source in raw mode", async () => {
		const r = await fetchContent(`${server.url}/page`, { mode: "raw", config: config() });
		assert.equal(r.kind, "html");
		assert.match(r.content, /^<html><head><title>Doc Title<\/title>/);
	});
	it("pretty-prints compact JSON and passes text/markdown through", async () => {
		const j = await fetchContent(`${server.url}/json`, { mode: "readable", config: config() });
		assert.equal(j.kind, "json");
		assert.equal(j.content, '{\n  "a": 1,\n  "b": [\n    1,\n    2\n  ]\n}');
		const t = await fetchContent(`${server.url}/text`, { mode: "readable", config: config() });
		assert.equal(t.kind, "text");
		assert.equal(t.title, "Heading");
		const m = await fetchContent(`${server.url}/md`, { mode: "readable", config: config() });
		assert.equal(m.kind, "markdown");
		assert.equal(m.title, "Readme");
	});
	it("sniffs HTML served as octet-stream and rejects true binaries", async () => {
		const s = await fetchContent(`${server.url}/octet-html`, { mode: "readable", config: config() });
		assert.equal(s.kind, "html");
		assert.equal(s.title, "Sniffed");
		const b = await fetchContent(`${server.url}/binary`, { mode: "readable", config: config() });
		assert.equal(b.kind, "error");
		assert.match(b.error ?? "", /Unsupported binary content: image\/png/);
	});
	it("reports HTTP errors with page title and guidance", async () => {
		const r = await fetchContent(`${server.url}/forbidden`, { mode: "readable", config: config() });
		assert.equal(r.kind, "error");
		assert.equal(r.status, 403);
		assert.match(r.error ?? "", /HTTP 403.*"Login required".*Access denied/);
		const nf = await fetchContent(`${server.url}/missing`, { mode: "readable", config: config() });
		assert.match(nf.error ?? "", /HTTP 404.*does not exist/);
	});
	it("warns about JavaScript-rendered shells", async () => {
		const r = await fetchContent(`${server.url}/shell`, { mode: "readable", config: config() });
		assert.equal(r.error, undefined);
		assert.match(r.warning ?? "", /JavaScript-rendered/);
	});
	it("follows redirects and records the final URL", async () => {
		const r = await fetchContent(`${server.url}/redirect`, { mode: "readable", config: config() });
		assert.equal(r.finalUrl, `${server.url}/page`);
		assert.equal(r.redirects, 1);
	});
	it("returns a blocked error (not a throw) when private networks are disallowed", async () => {
		const r = await fetchContent(`${server.url}/page`, { mode: "readable", config: config({ allowPrivateNetwork: false }), noCache: true });
		assert.equal(r.kind, "error");
		assert.match(r.error ?? "", /Blocked address 127\.0\.0\.1/);
	});
	it("returns errors for invalid input without throwing", async () => {
		const r = await fetchContent("mailto:x@y.z", { mode: "readable", config: config() });
		assert.match(r.error ?? "", /Unsupported URL scheme/);
	});
});
