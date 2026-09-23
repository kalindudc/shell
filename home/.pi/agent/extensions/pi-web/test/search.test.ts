import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { describe, it } from "node:test";
import { fileURLToPath } from "node:url";
import { CONFIG_DEFAULTS, type PiWebConfig } from "../config.ts";
import {
	decodeDuckDuckGoUrl,
	isProviderConfigured,
	matchesDomainFilters,
	parseBraveResponse,
	parseDomainFilters,
	parseDuckDuckGoHtml,
	parseDuckDuckGoLite,
	parseExaText,
	parseJsonRpcBody,
	parseSearxngResponse,
	resolveProviderChain,
} from "../search.ts";

const fixture = (name: string) => readFileSync(fileURLToPath(new URL(`./fixtures/${name}`, import.meta.url)), "utf8");

function config(overrides: Partial<PiWebConfig> = {}): PiWebConfig {
	return { ...CONFIG_DEFAULTS, configPath: "/dev/null", configFileFound: false, warnings: [], ...overrides };
}

describe("domain filters", () => {
	it("parses allow/deny lists and normalizes hosts", () => {
		assert.deepEqual(parseDomainFilters(["github.com", "-www.Reddit.com", "https://docs.python.org/3/", "*.example.org", " ", "-github.com/x"]), {
			allow: ["github.com", "docs.python.org", "example.org"],
			deny: ["reddit.com", "github.com"],
		});
	});
	it("matches subdomains and applies deny after allow", () => {
		const f = parseDomainFilters(["github.com", "-gist.github.com"]);
		assert.equal(matchesDomainFilters("https://github.com/a/b", f), true);
		assert.equal(matchesDomainFilters("https://www.github.com/a/b", f), true);
		assert.equal(matchesDomainFilters("https://docs.github.com/x", f), true);
		assert.equal(matchesDomainFilters("https://gist.github.com/x", f), false);
		assert.equal(matchesDomainFilters("https://notgithub.com/x", f), false);
		assert.equal(matchesDomainFilters("garbage", f), false);
		assert.equal(matchesDomainFilters("https://anything.example/", parseDomainFilters(undefined)), true);
	});
});

describe("DuckDuckGo", () => {
	it("decodes redirect links and drops ad trackers", () => {
		assert.equal(decodeDuckDuckGoUrl("//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Fa%3Fb%3D1&rut=x"), "https://example.com/a?b=1");
		assert.equal(decodeDuckDuckGoUrl("https://direct.example/page"), "https://direct.example/page");
		assert.equal(decodeDuckDuckGoUrl("https://duckduckgo.com/y.js?ad_domain=x"), null);
		assert.equal(decodeDuckDuckGoUrl("//duckduckgo.com/l/?uddg=javascript%3Aalert(1)"), null);
	});
	it("parses the html endpoint fixture, skipping ads and decoding entities", () => {
		const results = parseDuckDuckGoHtml(fixture("ddg-html.html"));
		assert.equal(results.length, 4, "ad excluded; duplicate kept at parse stage");
		assert.deepEqual(results[0], {
			title: "Markdown Guide",
			url: "https://www.markdownguide.org/",
			snippet: "The Markdown Guide is a free and open-source reference guide that explains how to use Markdown, the simple and easy-to-use markup language.",
		});
		assert.equal(results[1]?.url, "https://www.markdownguide.org/basic-syntax/");
		assert.match(results[1]?.snippet ?? "", /design document & more\.$/);
		assert.equal(results[2]?.title, "Writing on GitHub - GitHub Docs");
	});
	it("returns nothing for the bot-check page (detected upstream as a block)", () => {
		const blocked = fixture("ddg-blocked.html");
		assert.match(blocked, /anomaly-modal/);
		assert.deepEqual(parseDuckDuckGoHtml(blocked), []);
	});
	it("parses the lite endpoint layout and pairs snippets with links", () => {
		const lite = `<table>
<tr><td><a rel="nofollow" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fa.example%2F" class='result-link'>A Title</a></td></tr>
<tr><td class='result-snippet'>Snippet A</td></tr>
<tr><td><a rel="nofollow" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fb.example%2F" class='result-link'>B Title</a></td></tr>
<tr><td class='result-snippet'>Snippet <b>B</b></td></tr>
</table>`;
		assert.deepEqual(parseDuckDuckGoLite(lite), [
			{ title: "A Title", url: "https://a.example/", snippet: "Snippet A" },
			{ title: "B Title", url: "https://b.example/", snippet: "Snippet B" },
		]);
	});
});

describe("Exa", () => {
	it("extracts JSON-RPC payloads from SSE or plain JSON bodies", () => {
		assert.deepEqual(parseJsonRpcBody('event: message\ndata: {"result":{"content":[]}}\n\n'), { result: { content: [] } });
		assert.deepEqual(parseJsonRpcBody('{"error":{"code":-32000,"message":"bad"}}'), { error: { code: -32000, message: "bad" } });
		assert.equal(parseJsonRpcBody("garbage"), null);
	});
	it("parses Title/URL/Published/Highlights blocks", () => {
		const text = `Title: First Page
URL: https://one.example/a
Published: 2024-05-01T00:00:00.000Z
Author: N/A
Highlights:
> First highlight sentence.
...
Second highlight sentence.
---
Title: Second Page
URL: https://two.example/b
Published: N/A
Author: Someone
Text: Full text body here.
`;
		const results = parseExaText(text);
		assert.equal(results.length, 2);
		assert.deepEqual(results[0], { title: "First Page", url: "https://one.example/a", snippet: "First highlight sentence. Second highlight sentence.", age: "2024-05-01" });
		assert.deepEqual(results[1], { title: "Second Page", url: "https://two.example/b", snippet: "Full text body here.", age: undefined });
	});
	it("ignores blocks without an http(s) URL", () => {
		assert.deepEqual(parseExaText("Title: X\nURL: ftp://nope\n"), []);
	});
});

describe("Brave / SearXNG parsers", () => {
	it("maps Brave web and news results", () => {
		const results = parseBraveResponse({
			web: { results: [{ title: "T <b>1</b>", url: "https://a.example/", description: "D &amp; 1", age: "2 days ago" }, { title: "no url" }] },
			news: { results: [{ title: "N", url: "https://n.example/", description: "nd", age: "1 hour ago" }] },
		});
		assert.deepEqual(results, [
			{ title: "T 1", url: "https://a.example/", snippet: "D & 1", age: "2 days ago" },
			{ title: "N", url: "https://n.example/", snippet: "nd", age: "1 hour ago" },
		]);
	});
	it("maps SearXNG results", () => {
		const results = parseSearxngResponse({ results: [{ title: "S", url: "https://s.example/", content: "c", publishedDate: "2024-01-02T03:04:05", engine: "google" }] });
		assert.deepEqual(results, [{ title: "S", url: "https://s.example/", snippet: "c", age: "2024-01-02" }]);
	});
});

describe("routing", () => {
	it("auto chain includes keyed providers only when configured, keyless last", () => {
		assert.deepEqual(resolveProviderChain(undefined, config()), ["duckduckgo", "exa"]);
		assert.deepEqual(resolveProviderChain(undefined, config({ braveApiKey: "k" })), ["brave", "duckduckgo", "exa"]);
		assert.deepEqual(resolveProviderChain(undefined, config({ braveApiKey: "k", searxngUrl: "http://sx" })), ["brave", "searxng", "duckduckgo", "exa"]);
		assert.deepEqual(resolveProviderChain("exa", config()), ["exa"]);
		assert.deepEqual(resolveProviderChain(undefined, config({ provider: "brave" })), ["brave"]);
	});
	it("reports configuration state per provider", () => {
		assert.equal(isProviderConfigured("brave", config()), false);
		assert.equal(isProviderConfigured("brave", config({ braveApiKey: "k" })), true);
		assert.equal(isProviderConfigured("searxng", config()), false);
		assert.equal(isProviderConfigured("duckduckgo", config()), true);
		assert.equal(isProviderConfigured("exa", config()), true);
	});
});
