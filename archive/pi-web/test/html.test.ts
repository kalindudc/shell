import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { convertTokens, decodeEntities, extractDocument, htmlToMarkdown, htmlToText, quickTitle, tokenize } from "../html.ts";

describe("decodeEntities", () => {
	it("decodes named, decimal and hex entities", () => {
		assert.equal(decodeEntities("&amp;&lt;&gt;&quot;&#65;&#x42;&nbsp;&hellip;"), '&<>"AB\u00a0…');
	});
	it("leaves unknown or unterminated entities alone", () => {
		assert.equal(decodeEntities("&bogus; &amp x"), "&bogus; &amp x");
	});
	it("replaces surrogate code points with U+FFFD", () => {
		assert.equal(decodeEntities("&#xD800;"), "\ufffd");
	});
});

describe("tokenize", () => {
	it("parses tags, attributes (quoted, unquoted, valueless) and text", () => {
		const tokens = tokenize(`<a href="x>y" data-a='1' hidden>t</a><br/><img src=a.png alt=b>`);
		assert.deepEqual(tokens[0], { type: "open", name: "a", attrs: { href: "x>y", "data-a": "1", hidden: "" }, selfClosing: false });
		assert.deepEqual(tokens[1], { type: "text", value: "t" });
		assert.deepEqual(tokens[2], { type: "close", name: "a" });
		assert.deepEqual(tokens[3], { type: "open", name: "br", attrs: {}, selfClosing: true });
		assert.deepEqual(tokens[4], { type: "open", name: "img", attrs: { src: "a.png", alt: "b" }, selfClosing: true });
	});
	it("skips comments, doctype and treats script/style bodies as opaque", () => {
		const tokens = tokenize(`<!DOCTYPE html><!-- <p>no</p> --><script>if (a < b) { x = "<p>"; }</script><p>yes</p>`);
		const names = tokens.map((t) => (t.type === "text" ? `text:${t.value}` : `${t.type}:${t.name}`));
		assert.deepEqual(names, ["open:script", "close:script", "open:p", "text:yes", "close:p"]);
	});
	it("keeps <title> text as a raw text token", () => {
		const tokens = tokenize(`<title>A &amp; B</title>`);
		assert.deepEqual(tokens[1], { type: "text", value: "A &amp; B", raw: true });
	});
});

describe("htmlToMarkdown", () => {
	it("converts headings, emphasis, links and inline code", () => {
		const md = htmlToMarkdown(`<h2>Title</h2><p>Some <strong>bold</strong>, <em>em</em>, <a href="/x">link</a> and <code>a &lt; b</code>.</p>`, "https://ex.com/base/");
		assert.equal(md, "## Title\n\nSome **bold**, *em*, [link](https://ex.com/x) and `a < b`.");
	});
	it("renders nested and ordered lists with start offsets", () => {
		const md = htmlToMarkdown(`<ul><li>One</li><li>Two<ul><li>Nested</li></ul></li></ul><ol start="3"><li>Three</li><li>Four</li></ol>`);
		assert.equal(md, "- One\n- Two\n  - Nested\n\n3. Three\n4. Four");
	});
	it("renders fenced code blocks with language from <code class>", () => {
		const md = htmlToMarkdown(`<pre><code class="language-ts">const x = 1;\nif (x &lt; 2) {}</code></pre>`);
		assert.equal(md, "```ts\nconst x = 1;\nif (x < 2) {}\n```");
	});
	it("renders blockquotes and horizontal rules", () => {
		const md = htmlToMarkdown(`<blockquote><p>Quoted</p><p>Again</p></blockquote><hr><p>after</p>`);
		assert.equal(md, "> Quoted\n>\n> Again\n\n---\n\nafter");
	});
	it("renders GFM tables with header detection, caption, pipe escaping and colspan padding", () => {
		const md = htmlToMarkdown(`<table><caption>Cap</caption><thead><tr><th>A</th><th>B|C</th></tr></thead><tbody><tr><td>1</td><td>2</td></tr><tr><td colspan="2">wide</td></tr></tbody></table>`);
		assert.equal(md, "*Cap*\n\n| A | B\\|C |\n| --- | --- |\n| 1 | 2 |\n| wide |  |");
	});
	it("collapses a single-cell layout table into a paragraph", () => {
		assert.equal(htmlToMarkdown(`<table><tr><td>Just text</td></tr></table>`), "Just text");
	});
	it("drops scripts, styles, nav, forms, hidden and cookie-banner elements", () => {
		const md = htmlToMarkdown(
			`<nav><a href="/">Home</a></nav><style>p{}</style><form><input><button>Go</button></form><div hidden>hid</div><div aria-hidden="true">aria</div><div class="cookie-banner">Accept</div><div role="navigation">nav</div><p>Keep</p>`,
		);
		assert.equal(md, "Keep");
	});
	it("keeps header/footer inside article but drops top-level header/footer (document mode)", () => {
		const html = `<header>Site</header><article><header><h1>Post</h1></header><p>Body</p><footer>Tags</footer></article><footer>Site footer</footer>`;
		assert.equal(convertTokens(tokenize(html), { keepChrome: false }), "# Post\n\nBody\n\nTags");
		// Fragment mode keeps everything except nav/aside/scripts.
		assert.equal(htmlToMarkdown(html), "Site\n\n# Post\n\nBody\n\nTags\n\nSite footer");
	});
	it("recovers from unclosed inline elements when a block starts", () => {
		const md = htmlToMarkdown(`<p>Unclosed <a href="https://a.b/c">link<p>Next</p>`);
		assert.equal(md, "Unclosed [link](https://a.b/c)\n\nNext");
	});
	it("emits images only when they have alt text and are not tracking pixels", () => {
		const md = htmlToMarkdown(`<img src="/a.png" alt="Alt"><img src="/pixel.gif" width="1" height="1" alt="px"><img src="/noalt.png">`, "https://ex.com/");
		assert.equal(md, "![Alt](https://ex.com/a.png)");
	});
	it("autolinks when the anchor text equals the href and drops fragment/javascript links", () => {
		const md = htmlToMarkdown(`<a href="https://x.y/">https://x.y/</a> <a href="#frag">frag</a> <a href="javascript:void(0)">js</a>`);
		assert.equal(md, "<https://x.y/> frag js");
	});
	it("escapes text that would otherwise start a markdown list or heading", () => {
		assert.equal(htmlToMarkdown(`<p>1. Not a list</p><p># Not a heading</p><p>- nope</p>`), "1\\. Not a list\n\n\\# Not a heading\n\n\\- nope");
	});
	it("renders definition lists, details/summary and <br>", () => {
		assert.equal(htmlToMarkdown(`<dl><dt>Term</dt><dd>Def</dd></dl><details><summary>More</summary>Body</details><p>a<br>b</p>`), "**Term**\n: Def\n**More**\nBody\n\na\nb");
	});
	it("preserves whitespace inside <pre> and strips copy buttons", () => {
		assert.equal(htmlToMarkdown(`<pre><button>Copy</button>  indented\n\tline</pre>`), "```\n  indented\n\tline\n```");
	});
	it("does not leak the separating blank line into a <pre> that follows inline text", () => {
		assert.equal(htmlToMarkdown(`text<pre>code</pre>`), "text\n\n```\ncode\n```");
	});
	it("wraps <dt>/<summary> correctly when preceded by inline text", () => {
		assert.equal(htmlToMarkdown(`text<dl><dt>Term</dt><dd>Def</dd></dl>`), "text\n**Term**\n: Def");
		assert.equal(htmlToMarkdown(`x<details><summary>More</summary>Body</details>`), "x\n**More**\nBody");
	});
	it("converts large pages in linear time (regression guard for quadratic output building)", () => {
		const para = `<p>Lorem ipsum <b>dolor</b> sit amet, <a href="/x">consectetur</a> adipiscing elit sed do eiusmod.</p>\n`;
		let body = "";
		let i = 0;
		while (body.length < 2 * 1024 * 1024) body += `<h2>Section ${i++}</h2>${para.repeat(8)}<ul><li>one</li><li>two <code>x</code></li></ul>`;
		const html = `<html><head><title>Big</title></head><body><nav>nav</nav><main>${body}</main><footer>f</footer></body></html>`;
		const t0 = performance.now();
		const doc = extractDocument(html, "https://big.example/");
		const ms = performance.now() - t0;
		assert.equal(doc.contentRoot, "main");
		assert.ok(doc.markdown.length > 1_000_000);
		// Quadratic behaviour measured 80+ s here; linear runs in ~0.1 s. Generous bound for slow CI.
		assert.ok(ms < 3000, `2 MB conversion took ${ms.toFixed(0)} ms`);
	});
});

describe("quickTitle", () => {
	it("extracts and decodes <title> without converting the document", () => {
		assert.equal(quickTitle(`<html><head><title>\n  Login &amp; Sign in \n</title></head><body>${"<p>x</p>".repeat(10)}</body></html>`), "Login & Sign in");
		assert.equal(quickTitle("<html><body>no title</body></html>"), "");
	});
});

describe("extractDocument", () => {
	const page = (main: string, extra = "") => `<!DOCTYPE html><html lang="en"><head><title>Page Title | Site</title>
<meta property="og:title" content="Site"><meta name="description" content="Desc here"><base href="https://ex.com/docs/">
<link rel="canonical" href="/docs/page"></head><body><header><nav><a href="/">Home</a></nav></header>${extra}<main>${main}</main><footer>Footer</footer></body></html>`;

	it("prefers <title> over og:title and extracts description, base, canonical, lang", () => {
		const doc = extractDocument(page(`<h1>Hi</h1><p>${"Body text. ".repeat(40)}</p>`), "https://ex.com/docs/page?x=1");
		assert.equal(doc.title, "Page Title | Site");
		assert.equal(doc.description, "Desc here");
		assert.equal(doc.baseUrl, "https://ex.com/docs/");
		assert.equal(doc.canonicalUrl, "https://ex.com/docs/page");
		assert.equal(doc.lang, "en");
	});
	it("selects <main> as the content root when it holds most of the text", () => {
		const doc = extractDocument(page(`<h1>Hi</h1><p>${"Body text. ".repeat(40)}</p>`, `<div>${"Chrome. ".repeat(10)}</div>`));
		assert.equal(doc.contentRoot, "main");
		assert.match(doc.markdown, /^# Hi\n\nBody text\./);
		assert.doesNotMatch(doc.markdown, /Chrome\./);
	});
	it("prefers #mw-content-text over an enclosing <main>", () => {
		const doc = extractDocument(page(`<div class="lang-list">${"<a href='/l'>Lang</a> ".repeat(30)}</div><div id="mw-content-text"><p>${"Article. ".repeat(60)}</p></div>`));
		assert.equal(doc.contentRoot, "#mw-content-text");
		assert.doesNotMatch(doc.markdown, /Lang/);
	});
	it("falls back to body when the candidate holds too little of the text", () => {
		const doc = extractDocument(`<html><body><article><p>Teaser.</p></article><div>${"Real content. ".repeat(60)}</div></body></html>`);
		assert.equal(doc.contentRoot, "body");
		assert.match(doc.markdown, /Real content/);
	});
	it("skips a small <article> teaser in favour of an enclosing <main>", () => {
		const doc = extractDocument(page(`<article><p>Teaser.</p></article><div>${"Real content. ".repeat(60)}</div>`));
		assert.equal(doc.contentRoot, "main");
	});
	it("flags likely JS-rendered shells", () => {
		const doc = extractDocument(`<html><head><title>App</title><script src="a.js"></script><script src="b.js"></script><script src="c.js"></script></head><body><div id="root"></div></body></html>`);
		assert.equal(doc.likelyJsRendered, true);
		assert.equal(doc.markdown, "");
	});
	it("uses the first <h1> as the title when <title> and og:title are missing", () => {
		const doc = extractDocument(`<html><body><h1>Only <em>H1</em></h1><p>text</p></body></html>`);
		assert.equal(doc.title, "Only H1");
	});
});

describe("htmlToText", () => {
	it("strips tags and collapses whitespace", () => {
		assert.equal(htmlToText("The <b>Markdown</b>\n  Guide &amp; more<br>next"), "The Markdown Guide & more next");
	});
});
