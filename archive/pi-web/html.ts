/**
 * Dependency-free HTML → Markdown conversion.
 *
 * Pipeline:
 *   tokenize(html)            → flat token stream (open/close/text)
 *   selectContentRoot(tokens) → <main>/<article>/#content/... or <body>
 *   convert(tokens)           → GitHub-flavoured markdown
 *
 * The converter is a single pass over tokens with an element stack. Elements
 * that need to post-process their inner text (links, emphasis, code, quotes,
 * table cells) record a "mark" (output offset) on open and transform the slice
 * on close. This keeps memory flat and avoids building a DOM.
 */

// ---------------------------------------------------------------------------
// Entities
// ---------------------------------------------------------------------------

const NAMED_ENTITIES: Record<string, string> = {
	amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: "\u00a0", ensp: "\u2002", emsp: "\u2003", thinsp: "\u2009",
	shy: "", zwj: "\u200d", zwnj: "\u200c", lrm: "", rlm: "",
	copy: "©", reg: "®", trade: "™", deg: "°", plusmn: "±", para: "¶", sect: "§", micro: "µ", middot: "·", bull: "•",
	hellip: "…", mdash: "—", ndash: "–", lsquo: "‘", rsquo: "’", sbquo: "‚", ldquo: "“", rdquo: "”", bdquo: "„",
	laquo: "«", raquo: "»", lsaquo: "‹", rsaquo: "›", prime: "′", Prime: "″", dagger: "†", Dagger: "‡", permil: "‰",
	times: "×", divide: "÷", minus: "−", frac12: "½", frac14: "¼", frac34: "¾", sup1: "¹", sup2: "²", sup3: "³",
	cent: "¢", pound: "£", yen: "¥", euro: "€", curren: "¤", iexcl: "¡", iquest: "¿", brvbar: "¦", uml: "¨",
	ordf: "ª", ordm: "º", not: "¬", macr: "¯", acute: "´", cedil: "¸",
	larr: "←", uarr: "↑", rarr: "→", darr: "↓", harr: "↔", crarr: "↵", lArr: "⇐", rArr: "⇒", hArr: "⇔",
	forall: "∀", part: "∂", exist: "∃", empty: "∅", nabla: "∇", isin: "∈", notin: "∉", ni: "∋", prod: "∏", sum: "∑",
	lowast: "∗", radic: "√", prop: "∝", infin: "∞", ang: "∠", and: "∧", or: "∨", cap: "∩", cup: "∪", int: "∫",
	there4: "∴", sim: "∼", cong: "≅", asymp: "≈", ne: "≠", equiv: "≡", le: "≤", ge: "≥", sub: "⊂", sup: "⊃",
	nsub: "⊄", sube: "⊆", supe: "⊇", oplus: "⊕", otimes: "⊗", perp: "⊥", sdot: "⋅", loz: "◊", spades: "♠",
	clubs: "♣", hearts: "♥", diams: "♦", check: "✓", cross: "✗", star: "☆", starf: "★",
	Agrave: "À", Aacute: "Á", Acirc: "Â", Atilde: "Ã", Auml: "Ä", Aring: "Å", AElig: "Æ", Ccedil: "Ç", Egrave: "È",
	Eacute: "É", Ecirc: "Ê", Euml: "Ë", Igrave: "Ì", Iacute: "Í", Icirc: "Î", Iuml: "Ï", ETH: "Ð", Ntilde: "Ñ",
	Ograve: "Ò", Oacute: "Ó", Ocirc: "Ô", Otilde: "Õ", Ouml: "Ö", Oslash: "Ø", Ugrave: "Ù", Uacute: "Ú", Ucirc: "Û",
	Uuml: "Ü", Yacute: "Ý", THORN: "Þ", szlig: "ß", agrave: "à", aacute: "á", acirc: "â", atilde: "ã", auml: "ä",
	aring: "å", aelig: "æ", ccedil: "ç", egrave: "è", eacute: "é", ecirc: "ê", euml: "ë", igrave: "ì", iacute: "í",
	icirc: "î", iuml: "ï", eth: "ð", ntilde: "ñ", ograve: "ò", oacute: "ó", ocirc: "ô", otilde: "õ", ouml: "ö",
	oslash: "ø", ugrave: "ù", uacute: "ú", ucirc: "û", uuml: "ü", yacute: "ý", thorn: "þ", yuml: "ÿ", OElig: "Œ",
	oelig: "œ", Scaron: "Š", scaron: "š", Yuml: "Ÿ", fnof: "ƒ", circ: "ˆ", tilde: "˜",
	Alpha: "Α", Beta: "Β", Gamma: "Γ", Delta: "Δ", Epsilon: "Ε", Theta: "Θ", Lambda: "Λ", Pi: "Π", Sigma: "Σ",
	Omega: "Ω", alpha: "α", beta: "β", gamma: "γ", delta: "δ", epsilon: "ε", zeta: "ζ", eta: "η", theta: "θ",
	iota: "ι", kappa: "κ", lambda: "λ", mu: "μ", nu: "ν", xi: "ξ", pi: "π", rho: "ρ", sigma: "σ", tau: "τ",
	upsilon: "υ", phi: "φ", chi: "χ", psi: "ψ", omega: "ω",
};

export function decodeEntities(input: string): string {
	if (!input.includes("&")) return input;
	return input.replace(/&(#x[0-9a-f]+|#\d+|[a-z][a-z0-9]*);?/gi, (match, body: string) => {
		if (body[0] === "#") {
			const code = body[1]?.toLowerCase() === "x" ? parseInt(body.slice(2), 16) : parseInt(body.slice(1), 10);
			if (!Number.isFinite(code) || code <= 0 || code > 0x10ffff) return match;
			if (code >= 0xd800 && code <= 0xdfff) return "\ufffd";
			return String.fromCodePoint(code);
		}
		if (!match.endsWith(";")) return match; // be conservative with legacy unterminated entities
		const named = NAMED_ENTITIES[body];
		return named !== undefined ? named : match;
	});
}

// ---------------------------------------------------------------------------
// Tokenizer
// ---------------------------------------------------------------------------

export interface OpenToken {
	type: "open";
	name: string;
	attrs: Record<string, string>;
	selfClosing: boolean;
}
export interface CloseToken {
	type: "close";
	name: string;
}
export interface TextToken {
	type: "text";
	value: string;
	/** Text came from a raw-text element (title/textarea) — not marked up. */
	raw?: boolean;
}
export type Token = OpenToken | CloseToken | TextToken;

const VOID_ELEMENTS = new Set([
	"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr",
]);
/** Elements whose content is not HTML (skipped or taken verbatim). */
const RAW_TEXT_ELEMENTS = new Set(["script", "style", "textarea", "title", "xmp", "noscript", "template", "svg", "math", "iframe", "object", "noframes"]);
const RAW_TEXT_KEEP = new Set(["title", "textarea"]);

const ATTR_RE = /([^\s"'>/=]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/g;

function parseAttrs(source: string): Record<string, string> {
	const attrs: Record<string, string> = {};
	ATTR_RE.lastIndex = 0;
	let m: RegExpExecArray | null;
	while ((m = ATTR_RE.exec(source)) !== null) {
		const name = m[1]?.toLowerCase();
		if (!name || name in attrs) continue;
		attrs[name] = decodeEntities(m[2] ?? m[3] ?? m[4] ?? "");
	}
	return attrs;
}

export function tokenize(html: string): Token[] {
	const tokens: Token[] = [];
	const len = html.length;
	let i = 0;
	let textStart = 0;

	const flushText = (end: number) => {
		if (end > textStart) tokens.push({ type: "text", value: html.slice(textStart, end) });
	};

	while (i < len) {
		const lt = html.indexOf("<", i);
		if (lt === -1) break;
		const next = html[lt + 1];
		if (next === undefined) break;

		// Comments, doctype, CDATA, processing instructions
		if (next === "!" || next === "?") {
			flushText(lt);
			let end: number;
			if (html.startsWith("<!--", lt)) {
				end = html.indexOf("-->", lt + 4);
				end = end === -1 ? len : end + 3;
			} else if (html.startsWith("<![CDATA[", lt)) {
				end = html.indexOf("]]>", lt + 9);
				end = end === -1 ? len : end + 3;
			} else {
				end = html.indexOf(">", lt);
				end = end === -1 ? len : end + 1;
			}
			i = textStart = end;
			continue;
		}

		const isClose = next === "/";
		const nameStart = isClose ? lt + 2 : lt + 1;
		if (!/[a-zA-Z]/.test(html[nameStart] ?? "")) {
			i = lt + 1; // stray "<"
			continue;
		}
		let j = nameStart;
		while (j < len && /[a-zA-Z0-9:-]/.test(html[j] as string)) j++;
		const name = html.slice(nameStart, j).toLowerCase();

		// Find end of tag, honouring quoted attribute values
		let k = j;
		let quote: string | null = null;
		while (k < len) {
			const ch = html[k] as string;
			if (quote) {
				if (ch === quote) quote = null;
			} else if (ch === '"' || ch === "'") {
				quote = ch;
			} else if (ch === ">") {
				break;
			}
			k++;
		}
		if (k >= len) break;

		flushText(lt);
		if (isClose) {
			tokens.push({ type: "close", name });
			i = textStart = k + 1;
			continue;
		}

		const attrSource = html.slice(j, k);
		const selfClosing = /\/\s*$/.test(attrSource) || VOID_ELEMENTS.has(name);
		tokens.push({ type: "open", name, attrs: parseAttrs(attrSource.replace(/\/\s*$/, "")), selfClosing });
		i = textStart = k + 1;

		if (RAW_TEXT_ELEMENTS.has(name) && !selfClosing) {
			const closeRe = new RegExp(`</${name}\\s*>`, "ig");
			closeRe.lastIndex = i;
			const cm = closeRe.exec(html);
			const contentEnd = cm ? cm.index : len;
			if (RAW_TEXT_KEEP.has(name)) tokens.push({ type: "text", value: html.slice(i, contentEnd), raw: true });
			tokens.push({ type: "close", name });
			i = textStart = cm ? cm.index + cm[0].length : len;
		}
	}
	flushText(len);
	return tokens;
}

// ---------------------------------------------------------------------------
// Element classification
// ---------------------------------------------------------------------------

const BLOCK_ELEMENTS = new Set([
	"address", "article", "aside", "blockquote", "body", "caption", "center", "dd", "details", "dialog", "dir", "div",
	"dl", "dt", "fieldset", "figcaption", "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "header",
	"hgroup", "hr", "html", "legend", "li", "main", "menu", "nav", "ol", "p", "pre", "section", "summary", "table",
	"tbody", "td", "tfoot", "th", "thead", "tr", "ul",
]);
const INLINE_FORMAT = new Set(["a", "abbr", "b", "cite", "code", "del", "em", "i", "ins", "kbd", "mark", "q", "s", "samp", "small", "span", "strike", "strong", "sub", "sup", "tt", "u", "var"]);
/** Dropped entirely (with their content) wherever they appear. */
const NOISE_ELEMENTS = new Set([
	"script", "style", "noscript", "template", "svg", "math", "iframe", "object", "embed", "canvas", "video", "audio",
	"map", "button", "select", "option", "datalist", "input", "textarea", "label", "meter", "progress", "dialog",
	"menu", "nav", "aside", "form",
]);
const NOISE_ROLES = new Set(["navigation", "banner", "contentinfo", "complementary", "search", "dialog", "alertdialog", "menu", "menubar", "toolbar", "tooltip", "presentation"]);
const NOISE_CLASS_RE = /(?:^|[\s_-])(?:cookie|consent|gdpr|popup|modal|advert|advertisement|ads|ad-slot|sponsored|breadcrumbs?|skip-link|skip-to|sr-only|visually-hidden|screen-reader|share-buttons|social-share|newsletter|subscribe-box|sidebar|site-header|site-footer|global-nav|top-bar|announcement-bar|toc-toggle)(?:$|[\s_-])/i;

// ---------------------------------------------------------------------------
// Converter
// ---------------------------------------------------------------------------

interface Frame {
	name: string;
	/** Output mark (chunk index) taken when the element opened. */
	mark: number;
	attrs: Record<string, string>;
	href?: string;
	skip: boolean;
}

interface TableState {
	rows: Array<{ cells: string[]; header: boolean }>;
	row: { cells: string[]; header: boolean } | null;
	cellMark: number;
	cellHeader: boolean;
	caption: string;
}

export interface ConvertOptions {
	baseUrl?: string;
	/** Keep <header>/<footer> content (default: drop unless nested in article/main/section). <nav>/<aside> are always dropped. */
	keepChrome?: boolean;
}

function resolveUrl(href: string, base: string | undefined): string | null {
	const trimmed = href.trim();
	if (!trimmed || trimmed.startsWith("#") || /^(javascript|mailto|tel|data|vbscript):/i.test(trimmed)) return null;
	try {
		return base ? new URL(trimmed, base).href : new URL(trimmed).href;
	} catch {
		return null;
	}
}

function codeLanguage(attrs: Record<string, string>): string {
	const cls = `${attrs.class ?? ""} ${attrs["data-lang"] ?? ""} ${attrs["data-language"] ?? ""}`;
	const m = /(?:^|\s)(?:language|lang|highlight-source|brush:\s*)[-_ ]?([a-z0-9#+_-]+)/i.exec(cls);
	if (m?.[1]) return m[1].toLowerCase();
	const bare = /(?:^|\s)(js|javascript|ts|typescript|python|py|ruby|rb|go|golang|rust|java|c|cpp|csharp|sh|bash|shell|zsh|json|yaml|yml|toml|html|css|sql|xml|diff|dockerfile|makefile|kotlin|swift|php|scala|elixir|erlang|haskell|lua|perl|r|graphql|proto)(?:\s|$)/i.exec(cls);
	return bare?.[1]?.toLowerCase() ?? "";
}

function escapeCell(text: string): string {
	return text.replace(/\s*\n\s*/g, " ").replace(/\|/g, "\\|").trim();
}

function wrapInline(slice: string, marker: string): string {
	const leading = slice.match(/^\s*/)?.[0] ?? "";
	const trailing = slice.match(/\s*$/)?.[0] ?? "";
	const core = slice.trim();
	if (!core) return slice;
	if (core.startsWith(marker) && core.endsWith(marker)) return slice;
	return `${leading}${marker}${core}${marker}${trailing}`;
}

/**
 * Append-only output buffer built from string chunks.
 *
 * All "what does the output currently end with" questions are answered from a
 * tracked two-character tail, and marks are chunk indices, so the converter
 * never flattens or re-scans the accumulated output. This keeps conversion
 * linear in the input size (a naive `out += …` + `out.endsWith()` loop is
 * quadratic: V8 cons-strings are flattened on every inspection).
 */
class OutputBuffer {
	private chunks: string[] = [];
	private tail = "";

	get mark(): number {
		return this.chunks.length;
	}
	get isEmpty(): boolean {
		return this.chunks.length === 0;
	}
	push(s: string): void {
		if (!s) return;
		this.chunks.push(s);
		this.tail = s.length >= 2 ? s.slice(-2) : (this.tail + s).slice(-2);
	}
	/** `suffix` must be at most two characters long. */
	endsWith(suffix: string): boolean {
		return this.tail.endsWith(suffix);
	}
	endsWithWhitespace(): boolean {
		return this.chunks.length === 0 || /\s$/.test(this.tail);
	}
	/** Text emitted since `mark`. */
	since(mark: number): string {
		if (mark >= this.chunks.length) return "";
		if (mark === this.chunks.length - 1) return this.chunks[mark] as string;
		return this.chunks.slice(mark).join("");
	}
	/** Discard everything emitted since `mark`. */
	truncate(mark: number): void {
		if (mark >= this.chunks.length) return;
		this.chunks.length = mark;
		this.recomputeTail();
	}
	/** Remove trailing spaces/tabs (not newlines). */
	trimTrailingSpaces(): void {
		while (this.chunks.length) {
			const last = this.chunks[this.chunks.length - 1] as string;
			const trimmed = last.replace(/[ \t]+$/, "");
			if (trimmed === last) return;
			if (trimmed) {
				this.chunks[this.chunks.length - 1] = trimmed;
				break;
			}
			this.chunks.pop();
		}
		this.recomputeTail();
	}
	join(): string {
		return this.chunks.join("");
	}
	private recomputeTail(): void {
		let t = "";
		for (let i = this.chunks.length - 1; i >= 0 && t.length < 2; i--) t = (this.chunks[i] as string).slice(-2) + t;
		this.tail = t.slice(-2);
	}
}

class MarkdownBuilder {
	private readonly buf = new OutputBuffer();
	private preDepth = 0;
	private skipDepth = 0;
	private chromeDepth = 0; // inside article/main/section → keep header/footer
	private stack: Frame[] = [];
	private lists: Array<{ ordered: boolean; index: number; start: number }> = [];
	private tables: TableState[] = [];
	private readonly base: string | undefined;
	private readonly keepChrome: boolean;
	/** Language hint from a <code class="language-x"> directly inside <pre>. */
	private pendingCodeLang = "";
	/** WHATWG URL parsing dominates conversion time on link-heavy pages; hrefs repeat a lot. */
	private readonly urlCache = new Map<string, string | null>();

	constructor(options: ConvertOptions) {
		this.base = options.baseUrl;
		this.keepChrome = options.keepChrome ?? false;
	}

	private resolve(href: string): string | null {
		const cached = this.urlCache.get(href);
		if (cached !== undefined) return cached;
		const resolved = resolveUrl(href, this.base);
		if (this.urlCache.size >= 20_000) this.urlCache.clear();
		this.urlCache.set(href, resolved);
		return resolved;
	}

	// -- output helpers -----------------------------------------------------

	private append(s: string) {
		if (this.skipDepth > 0) return;
		this.buf.push(s);
	}
	private ensureNewline() {
		if (this.skipDepth > 0 || this.buf.isEmpty) return;
		if (!this.buf.endsWith("\n")) this.buf.push("\n");
	}
	private ensureBlankLine() {
		if (this.skipDepth > 0 || this.buf.isEmpty) return;
		if (this.buf.endsWith("\n\n")) return;
		this.buf.trimTrailingSpaces();
		if (this.buf.isEmpty) return;
		this.buf.push(this.buf.endsWith("\n") ? "\n" : "\n\n");
	}
	private endsWithWhitespace(): boolean {
		return this.buf.endsWithWhitespace();
	}

	// -- text -----------------------------------------------------------------

	text(token: TextToken) {
		if (this.skipDepth > 0) return;
		const decoded = decodeEntities(token.value);
		if (this.preDepth > 0) {
			this.buf.push(decoded.replace(/\r\n?/g, "\n"));
			return;
		}
		let s = decoded.replace(/[\s\u00a0]+/g, " ");
		if (!s) return;
		if (s === " ") {
			if (!this.endsWithWhitespace()) this.buf.push(" ");
			return;
		}
		if (s.startsWith(" ") && this.endsWithWhitespace()) s = s.slice(1);
		// Escape characters that would otherwise be read as markdown syntax at line start.
		if (this.buf.isEmpty || this.buf.endsWith("\n")) {
			s = s.replace(/^([#>*+-])(\s)/, "\\$1$2").replace(/^(\d+)\.(\s)/, "$1\\.$2");
		}
		this.buf.push(s);
	}

	// -- elements -----------------------------------------------------------

	private isNoise(name: string, attrs: Record<string, string>): boolean {
		if (NOISE_ELEMENTS.has(name)) return true;
		if ((name === "header" || name === "footer") && !this.keepChrome && this.chromeDepth === 0) return true;
		if (attrs.hidden !== undefined || attrs["aria-hidden"] === "true") return true;
		if (attrs.role && NOISE_ROLES.has(attrs.role.toLowerCase())) return true;
		const style = attrs.style ?? "";
		if (/display\s*:\s*none|visibility\s*:\s*hidden/i.test(style)) return true;
		if (name === "div" || name === "section" || name === "ul" || name === "span" || name === "p") {
			const idClass = `${attrs.id ?? ""} ${attrs.class ?? ""}`;
			if (idClass.trim() && NOISE_CLASS_RE.test(idClass)) return true;
		}
		return false;
	}

	private closeInlineFrames() {
		while (this.stack.length && INLINE_FORMAT.has((this.stack[this.stack.length - 1] as Frame).name)) {
			this.closeFrame(this.stack.pop() as Frame);
		}
	}

	open(token: OpenToken) {
		const { name, attrs } = token;
		const frame: Frame = { name, mark: this.buf.mark, attrs, skip: false };

		if (this.skipDepth > 0 || this.isNoise(name, attrs)) {
			if (!token.selfClosing) {
				frame.skip = true;
				this.skipDepth++;
				this.stack.push(frame);
			}
			return;
		}

		if (this.preDepth > 0) {
			if (name === "br") this.buf.push("\n");
			if (!token.selfClosing) this.stack.push(frame);
			return;
		}

		if (BLOCK_ELEMENTS.has(name)) this.closeInlineFrames();

		switch (name) {
			case "br":
				this.buf.push("\n");
				return;
			case "hr":
				this.ensureBlankLine();
				this.append("---");
				this.ensureBlankLine();
				return;
			case "wbr":
				return;
			case "img": {
				const alt = (attrs.alt ?? "").trim();
				const src = this.resolve(attrs.src ?? attrs["data-src"] ?? "");
				const tiny = (Number(attrs.width) > 0 && Number(attrs.width) <= 2) || (Number(attrs.height) > 0 && Number(attrs.height) <= 2);
				if (alt && src && !tiny) {
					if (!this.endsWithWhitespace()) this.buf.push(" ");
					this.buf.push(`![${alt.replace(/[[\]]/g, "")}](${src})`);
				}
				return;
			}
			case "meta":
			case "link":
			case "base":
			case "input":
			case "source":
			case "track":
			case "param":
			case "col":
			case "area":
				return;
		}

		if (token.selfClosing) return;

		switch (name) {
			case "article":
			case "main":
			case "section":
				this.chromeDepth++;
				this.ensureBlankLine();
				break;
			case "p":
			case "figure":
				this.ensureBlankLine();
				break;
			case "div":
			case "figcaption":
			case "address":
			case "fieldset":
			case "center":
			case "hgroup":
			case "details":
				this.ensureNewline();
				break;
			case "h1": case "h2": case "h3": case "h4": case "h5": case "h6":
				this.ensureBlankLine();
				this.append(`${"#".repeat(Number(name[1]))} `);
				break;
			case "summary":
			case "dt":
			case "legend":
				this.ensureNewline();
				frame.mark = this.buf.mark; // content only; wrapped in ** on close
				break;
			case "dd":
				this.ensureNewline();
				this.append(": ");
				break;
			case "ul":
			case "ol": {
				if (this.lists.length === 0) this.ensureBlankLine();
				else this.ensureNewline();
				const start = Number.parseInt(attrs.start ?? "1", 10);
				this.lists.push({ ordered: name === "ol", index: 0, start: Number.isFinite(start) ? start : 1 });
				break;
			}
			case "li": {
				this.ensureNewline();
				const list = this.lists[this.lists.length - 1];
				const depth = Math.max(0, this.lists.length - 1);
				if (list) {
					list.index++;
					const marker = list.ordered ? `${list.start + list.index - 1}. ` : "- ";
					this.append(`${"  ".repeat(depth)}${marker}`);
				} else {
					this.append("- ");
				}
				break;
			}
			case "blockquote":
				this.ensureBlankLine();
				frame.mark = this.buf.mark; // content only
				break;
			case "pre":
				this.ensureBlankLine();
				frame.mark = this.buf.mark; // content only
				this.preDepth++;
				break;
			case "a":
				frame.href = this.resolve(attrs.href ?? "") ?? undefined;
				break;
			case "table":
				this.ensureBlankLine();
				this.tables.push({ rows: [], row: null, cellMark: 0, cellHeader: false, caption: "" });
				break;
			case "tr": {
				const t = this.tables[this.tables.length - 1];
				if (t) t.row = { cells: [], header: false };
				break;
			}
			case "th":
			case "td": {
				const t = this.tables[this.tables.length - 1];
				if (t) {
					t.cellMark = this.buf.mark;
					t.cellHeader = name === "th";
				}
				break;
			}
		}
		this.stack.push(frame);
	}

	close(token: CloseToken) {
		let idx = -1;
		for (let i = this.stack.length - 1; i >= 0; i--) {
			if ((this.stack[i] as Frame).name === token.name) {
				idx = i;
				break;
			}
		}
		if (idx === -1) return; // stray close tag
		while (this.stack.length > idx) {
			this.closeFrame(this.stack.pop() as Frame);
		}
	}

	private closeFrame(frame: Frame) {
		if (frame.skip) {
			this.skipDepth--;
			return;
		}
		if (this.skipDepth > 0) return;
		const { name } = frame;

		if (this.preDepth > 0 && name !== "pre") return;

		switch (name) {
			case "article":
			case "main":
			case "section":
				this.chromeDepth = Math.max(0, this.chromeDepth - 1);
				this.ensureBlankLine();
				break;
			case "p":
			case "figure":
			case "h1": case "h2": case "h3": case "h4": case "h5": case "h6":
				this.ensureBlankLine();
				break;
			case "blockquote": {
				const slice = this.buf.since(frame.mark).replace(/^\n+|\n+$/g, "");
				this.buf.truncate(frame.mark);
				if (slice.trim()) {
					this.ensureBlankLine();
					this.buf.push(
						slice
							.split("\n")
							.map((l) => (l.trim() ? `> ${l}` : ">"))
							.join("\n"),
					);
				}
				this.ensureBlankLine();
				break;
			}
			case "div":
			case "figcaption":
			case "address":
			case "fieldset":
			case "center":
			case "hgroup":
			case "details":
			case "dd":
			case "li":
				this.ensureNewline();
				break;
			case "summary":
			case "dt":
			case "legend": {
				const core = this.buf.since(frame.mark).trim();
				this.buf.truncate(frame.mark);
				if (core) this.buf.push(`**${core}**`);
				this.ensureNewline();
				break;
			}
			case "ul":
			case "ol":
				this.lists.pop();
				if (this.lists.length === 0) this.ensureBlankLine();
				else this.ensureNewline();
				break;
			case "pre": {
				this.preDepth--;
				const inner = this.buf.since(frame.mark).replace(/^\n+/, "").replace(/\s+$/, "");
				this.buf.truncate(frame.mark);
				const lang = codeLanguage(frame.attrs) || this.pendingCodeLang;
				this.pendingCodeLang = "";
				const fence = inner.includes("```") ? "````" : "```";
				this.ensureBlankLine();
				this.buf.push(`${fence}${lang}\n${inner}\n${fence}`);
				this.ensureBlankLine();
				break;
			}
			case "code":
			case "kbd":
			case "samp":
			case "var":
			case "tt": {
				const slice = this.buf.since(frame.mark);
				const core = slice.trim();
				if (!core) break;
				this.buf.truncate(frame.mark);
				if (core.includes("\n")) {
					// Multi-line inline code: treat as fenced block
					this.ensureBlankLine();
					this.buf.push(`\`\`\`${codeLanguage(frame.attrs)}\n${core}\n\`\`\``);
					this.ensureBlankLine();
				} else {
					const ticks = core.includes("`") ? "``" : "`";
					const leading = slice.match(/^\s*/)?.[0] ?? "";
					const trailing = slice.match(/\s*$/)?.[0] ?? "";
					this.buf.push(`${leading}${ticks}${core}${ticks}${trailing}`);
				}
				break;
			}
			case "strong":
			case "b":
				this.replaceSince(frame.mark, wrapInline(this.buf.since(frame.mark), "**"));
				break;
			case "em":
			case "i":
			case "cite":
			case "dfn":
				this.replaceSince(frame.mark, wrapInline(this.buf.since(frame.mark), "*"));
				break;
			case "del":
			case "s":
			case "strike":
				this.replaceSince(frame.mark, wrapInline(this.buf.since(frame.mark), "~~"));
				break;
			case "q":
				this.replaceSince(frame.mark, `"${this.buf.since(frame.mark).trim()}"`);
				break;
			case "a": {
				const slice = this.buf.since(frame.mark);
				const text = slice.trim();
				if (!text) {
					this.buf.truncate(frame.mark);
					break;
				}
				if (!frame.href) break;
				const leading = slice.match(/^\s*/)?.[0] ?? "";
				const trailing = slice.match(/\s*$/)?.[0] ?? "";
				const isImageOnly = /^!\[[^\]]*\]\([^)]*\)$/.test(text);
				const display = text.replace(/\s*\n\s*/g, " ");
				const link = display === frame.href || display === frame.href.replace(/\/$/, "")
					? `<${frame.href}>`
					: isImageOnly
						? `[${display}](${frame.href})`
						: `[${display.replace(/\]/g, "\\]")}](${frame.href})`;
				this.replaceSince(frame.mark, `${leading}${link}${trailing}`);
				break;
			}
			case "caption": {
				const t = this.tables[this.tables.length - 1];
				const slice = this.buf.since(frame.mark).trim();
				this.buf.truncate(frame.mark);
				if (t) t.caption = slice;
				break;
			}
			case "th":
			case "td": {
				const t = this.tables[this.tables.length - 1];
				if (!t) break;
				const content = escapeCell(this.buf.since(t.cellMark));
				this.buf.truncate(t.cellMark);
				if (!t.row) t.row = { cells: [], header: false };
				t.row.cells.push(content);
				if (t.cellHeader) t.row.header = true;
				const span = Number.parseInt(frame.attrs.colspan ?? "1", 10);
				for (let s = 1; s < Math.min(span, 10); s++) t.row.cells.push("");
				break;
			}
			case "tr": {
				const t = this.tables[this.tables.length - 1];
				if (t?.row) {
					if (t.row.cells.some((c) => c)) t.rows.push(t.row);
					t.row = null;
				}
				break;
			}
			case "table": {
				const t = this.tables.pop();
				// Anything emitted directly inside <table> (outside cells) is discarded.
				this.buf.truncate(frame.mark);
				if (!t || t.rows.length === 0) break;
				this.ensureBlankLine();
				if (t.caption) this.buf.push(`*${t.caption}*\n\n`);
				const cols = Math.max(...t.rows.map((r) => r.cells.length));
				if (t.rows.length === 1 && cols === 1) {
					this.buf.push((t.rows[0] as { cells: string[] }).cells[0] ?? "");
					this.ensureBlankLine();
					break;
				}
				const pad = (row: string[]) => [...row, ...Array(Math.max(0, cols - row.length)).fill("")];
				const first = t.rows[0] as { cells: string[]; header: boolean };
				const hasHeader = first.header;
				const headerCells = hasHeader ? pad(first.cells) : Array(cols).fill("");
				const bodyRows = hasHeader ? t.rows.slice(1) : t.rows;
				const lines = [
					`| ${headerCells.join(" | ")} |`,
					`| ${Array(cols).fill("---").join(" | ")} |`,
					...bodyRows.map((r) => `| ${pad(r.cells).join(" | ")} |`),
				];
				this.buf.push(lines.join("\n"));
				this.ensureBlankLine();
				break;
			}
		}
	}

	private replaceSince(mark: number, text: string) {
		this.buf.truncate(mark);
		this.buf.push(text);
	}

	finish(): string {
		while (this.stack.length) this.closeFrame(this.stack.pop() as Frame);
		return this.buf
			.join()
			.replace(/[ \t]+\n/g, "\n")
			.replace(/\n{3,}/g, "\n\n")
			.trim();
	}

	/** Inspect a code element opening inside pre to capture language. */
	noteCodeInPre(attrs: Record<string, string>) {
		if (this.preDepth > 0 && !this.pendingCodeLang) this.pendingCodeLang = codeLanguage(attrs);
	}

	inPre(): boolean {
		return this.preDepth > 0;
	}
}

export function convertTokens(tokens: Token[], options: ConvertOptions = {}): string {
	const b = new MarkdownBuilder(options);
	for (const token of tokens) {
		if (token.type === "text") b.text(token);
		else if (token.type === "open") {
			if (token.name === "code" && b.inPre()) b.noteCodeInPre(token.attrs);
			b.open(token);
		} else b.close(token);
	}
	return b.finish();
}

// ---------------------------------------------------------------------------
// Document-level extraction
// ---------------------------------------------------------------------------

export interface HtmlDocument {
	title: string;
	description: string;
	baseUrl: string | undefined;
	lang: string;
	/** Markdown of the selected content root. */
	markdown: string;
	/** Which root was used (for diagnostics), e.g. "main", "article", "#content", "body". */
	contentRoot: string;
	/** Heuristic: page looks like a client-side rendered shell. */
	likelyJsRendered: boolean;
	/** Canonical URL from <link rel=canonical>, if any. */
	canonicalUrl?: string;
}

/** Find the index of the matching close token for the open token at `start`. */
function findMatchingClose(tokens: Token[], start: number): number {
	const open = tokens[start];
	if (!open || open.type !== "open" || open.selfClosing) return start;
	let depth = 0;
	for (let i = start; i < tokens.length; i++) {
		const t = tokens[i] as Token;
		if (t.type === "open" && t.name === open.name && !t.selfClosing) depth++;
		else if (t.type === "close" && t.name === open.name) {
			depth--;
			if (depth === 0) return i;
		}
	}
	return tokens.length - 1;
}

interface Candidate {
	label: string;
	match: (t: OpenToken) => boolean;
}

/** Ordered most-specific first; the first candidate holding ≥35% of the body text wins. */
const CONTENT_CANDIDATES: Candidate[] = [
	{ label: "#mw-content-text", match: (t) => t.attrs.id === "mw-content-text" },
	{ label: ".markdown-body", match: (t) => /(^|\s)markdown-body(\s|$)/.test(t.attrs.class ?? "") },
	{ label: "#readme", match: (t) => t.attrs.id === "readme" },
	{ label: "article", match: (t) => t.name === "article" },
	{ label: "[role=main]", match: (t) => (t.attrs.role ?? "").toLowerCase() === "main" },
	{ label: "main", match: (t) => t.name === "main" },
	{ label: "#content", match: (t) => t.attrs.id === "content" || t.attrs.id === "main-content" || t.attrs.id === "main" },
	{ label: ".content", match: (t) => /(^|\s)(post-content|entry-content|article-content|article-body|post-body|page-content|content|document|docs-content|md-content|theme-doc-markdown)(\s|$)/.test(t.attrs.class ?? "") },
];

function textLength(markdown: string): number {
	return markdown.replace(/\s+/g, " ").length;
}

/**
 * Cheap non-whitespace character count of the text tokens in a range.
 * Used to rank content-root candidates without running the converter on each.
 */
function rawTextLength(tokens: Token[], start = 0, end = tokens.length): number {
	let n = 0;
	for (let i = start; i < end; i++) {
		const t = tokens[i] as Token;
		if (t.type !== "text" || t.raw) continue;
		const v = t.value;
		for (let j = 0; j < v.length; j++) {
			const c = v.charCodeAt(j);
			if (c > 32 && c !== 0xa0) n++;
		}
	}
	return n;
}

/** Cheap `<title>` extraction (no conversion) for error pages and diagnostics. */
export function quickTitle(html: string): string {
	const m = /<title[^>]*>([\s\S]{0,2000}?)<\/title>/i.exec(html);
	return m?.[1] ? decodeEntities(m[1]).replace(/\s+/g, " ").trim() : "";
}

export function extractDocument(html: string, url?: string): HtmlDocument {
	const tokens = tokenize(html);

	let title = "";
	let ogTitle = "";
	let description = "";
	let baseUrl = url;
	let lang = "";
	let canonicalUrl: string | undefined;
	let firstH1 = "";

	for (let i = 0; i < tokens.length; i++) {
		const t = tokens[i] as Token;
		if (t.type !== "open") continue;
		if (t.name === "html" && t.attrs.lang) lang = t.attrs.lang;
		else if (t.name === "title" && !title) {
			const next = tokens[i + 1];
			if (next?.type === "text") title = decodeEntities(next.value).replace(/\s+/g, " ").trim();
		} else if (t.name === "meta") {
			const key = (t.attrs.property ?? t.attrs.name ?? "").toLowerCase();
			const content = (t.attrs.content ?? "").trim();
			if (!content) continue;
			if (key === "og:title" && !ogTitle) ogTitle = content;
			else if ((key === "description" || key === "og:description") && !description) description = content;
		} else if (t.name === "base" && t.attrs.href && url) {
			try {
				baseUrl = new URL(t.attrs.href, url).href;
			} catch {
				/* ignore bad base */
			}
		} else if (t.name === "link" && (t.attrs.rel ?? "").toLowerCase() === "canonical" && t.attrs.href) {
			canonicalUrl = resolveUrl(t.attrs.href, url) ?? undefined;
		}
		if (t.name === "body") break;
	}

	// Body slice (or whole doc when no <body>)
	const bodyIdx = tokens.findIndex((t) => t.type === "open" && t.name === "body");
	const bodyTokens = bodyIdx === -1 ? tokens : tokens.slice(bodyIdx + 1, findMatchingClose(tokens, bodyIdx));

	if (!title && !ogTitle) {
		const h1 = bodyTokens.findIndex((t) => t.type === "open" && t.name === "h1");
		if (h1 !== -1) {
			const end = findMatchingClose(bodyTokens, h1);
			firstH1 = convertTokens(bodyTokens.slice(h1 + 1, end), { baseUrl, keepChrome: true }).replace(/[*_`#]/g, "").replace(/\s+/g, " ").trim();
		}
	}

	// Pick a content root by cheap text-length estimates, then convert ONCE.
	const bodyRaw = rawTextLength(bodyTokens);
	let markdown: string | undefined;
	let contentRoot = "body";
	for (const candidate of CONTENT_CANDIDATES) {
		const idx = bodyTokens.findIndex((t) => t.type === "open" && !t.selfClosing && candidate.match(t));
		if (idx === -1) continue;
		const end = findMatchingClose(bodyTokens, idx);
		const raw = rawTextLength(bodyTokens, idx + 1, end);
		if (raw < 150 || raw < bodyRaw * 0.35) continue;
		const md = convertTokens(bodyTokens.slice(idx + 1, end), { baseUrl, keepChrome: true });
		if (textLength(md) >= 200) {
			markdown = md;
			contentRoot = candidate.label;
			break;
		}
	}
	if (markdown === undefined) markdown = convertTokens(bodyTokens, { baseUrl });

	const finalTitle = (title || ogTitle || firstH1).trim();
	const likelyJsRendered =
		textLength(markdown) < 300 &&
		(/id=["'](?:root|app|__next|__nuxt|main-app|svelte)["']/i.test(html) ||
			/data-reactroot|ng-version=|data-server-rendered|enable javascript|requires javascript/i.test(html) ||
			(html.match(/<script\b/gi)?.length ?? 0) >= 3);

	return { title: finalTitle, description, baseUrl, lang, markdown, contentRoot, likelyJsRendered, canonicalUrl };
}

/** Convert an HTML fragment/string to markdown (no content-root selection). */
export function htmlToMarkdown(html: string, baseUrl?: string): string {
	return convertTokens(tokenize(html), { baseUrl, keepChrome: true });
}

/** Strip all tags and collapse whitespace (for snippets). */
export function htmlToText(html: string): string {
	let text = "";
	for (const t of tokenize(html)) {
		if (t.type === "text") text += decodeEntities(t.value);
		else if (t.type === "open" && (t.name === "br" || BLOCK_ELEMENTS.has(t.name))) text += " ";
	}
	return text.replace(/\s+/g, " ").trim();
}
