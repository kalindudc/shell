/**
 * Minimal bash lexer and parser for the bash guard. No dependencies.
 *
 * It covers what agents actually write: quoting, escapes, line continuations,
 * comments, command/process/arithmetic substitution, heredocs, redirections,
 * pipelines, and-or lists, subshells, groups, if/while/until/for/case and
 * function definitions. Anything else raises ShellSyntaxError so the caller
 * can fall back to conservative text matching.
 *
 * All offsets are positions in the source string handed to parseScript.
 */

export class ShellSyntaxError extends Error {}

export interface Sub {
	kind: "command" | "backtick" | "process" | "arith";
	/** Offset of the `$`, backtick, `<` or `>` that opens the substitution. */
	outerStart: number;
	/** Body span (end exclusive). */
	start: number;
	end: number;
	text: string;
}

export interface Word {
	text: string;
	start: number;
	end: number;
	/** Top-level substitutions inside this word. */
	subs: Sub[];
}

export interface Heredoc {
	delimiter: string;
	quoted: boolean;
	stripTabs: boolean;
	bodyStart: number;
	bodyEnd: number;
}

export interface Redirect {
	op: string;
	target: Word;
	heredoc?: Heredoc;
}

export interface SimpleCommand {
	type: "simple";
	words: Word[];
	redirects: Redirect[];
	start: number;
	end: number;
}

export type Command =
	| SimpleCommand
	| { type: "subshell" | "group"; body: List; redirects: Redirect[] }
	| { type: "if"; clauses: Array<{ cond: List; body: List }>; elseBody: List | null; redirects: Redirect[] }
	| { type: "while"; cond: List; body: List; redirects: Redirect[] }
	| { type: "for"; name: string; words: Word[] | null; body: List; redirects: Redirect[] }
	| { type: "case"; subject: Word; items: Array<{ patterns: Word[]; body: List }>; redirects: Redirect[] }
	| { type: "function"; name: string; body: Command };

export interface Pipeline {
	negated: boolean;
	commands: Command[];
}

export interface AndOr {
	first: Pipeline;
	rest: Array<{ op: "&&" | "||"; pipeline: Pipeline }>;
}

export type List = Array<{ andOr: AndOr; background: boolean }>;

type Token =
	| { kind: "word"; word: Word; start: number; end: number }
	| { kind: "op"; op: string; start: number; end: number }
	| { kind: "redirect"; redirect: Redirect; start: number; end: number }
	| { kind: "newline" | "eof"; start: number; end: number };

/** Sticky, so it matches at `lastIndex` without slicing the source. */
const REDIRECT = /(\d*)(<<<|<<-|<<|<>|<&|>>|>&|>\||&>>|&>|<|>)/y;

/** The control operator starting at src[i], if any. */
function operatorAt(src: string, i: number): string | null {
	const c = src[i];
	const n = src[i + 1];
	switch (c) {
		case ";":
			if (n === ";") return src[i + 2] === "&" ? ";;&" : ";;";
			return n === "&" ? ";&" : ";";
		case "&":
			return n === "&" ? "&&" : "&";
		case "|":
			return n === "|" ? "||" : n === "&" ? "|&" : "|";
		case "(":
		case ")":
			return c;
		default:
			return null;
	}
}

function isRedirectStart(c: string): boolean {
	return c === "<" || c === ">" || c === "&" || (c >= "0" && c <= "9");
}
const KEEPS_COMMAND_START = new Set(["!", "{", "if", "then", "else", "elif", "do", "while", "until", "time"]);
const LIST_END_OPS = new Set([")", ";;", ";&", ";;&"]);
const MISPLACED_WORDS = new Set(["then", "else", "elif", "fi", "do", "done", "esac", "}"]);

// ---------------------------------------------------------------- lexer

function closeSingle(src: string, i: number): number {
	const end = src.indexOf("'", i + 1);
	if (end < 0) throw new ShellSyntaxError("unterminated single quote");
	return end + 1;
}

function readDouble(src: string, j: number, subs: Sub[]): number {
	while (j < src.length) {
		const c = src[j];
		if (c === '"') return j + 1;
		if (c === "\\") j += 2;
		else if (c === "$") j = readDollar(src, j, subs, true);
		else if (c === "`") j = readBacktick(src, j, subs);
		else j++;
	}
	throw new ShellSyntaxError("unterminated double quote");
}

function readBacktick(src: string, i: number, subs: Sub[]): number {
	let j = i + 1;
	while (j < src.length && src[j] !== "`") j += src[j] === "\\" ? 2 : 1;
	if (j >= src.length) throw new ShellSyntaxError("unterminated backtick");
	subs.push({ kind: "backtick", outerStart: i, start: i + 1, end: j, text: src.slice(i + 1, j) });
	return j + 1;
}

function readParenSub(src: string, outer: number, bodyStart: number, kind: Sub["kind"], subs: Sub[]): number {
	const end = lex(src, bodyStart, true).end;
	subs.push({ kind, outerStart: outer, start: bodyStart, end, text: src.slice(bodyStart, end) });
	return end + 1;
}

function readArith(src: string, i: number, subs: Sub[]): number {
	let depth = 0;
	for (let j = i + 1; j < src.length; j++) {
		if (src[j] === "(") depth++;
		else if (src[j] === ")" && --depth === 0) {
			subs.push({ kind: "arith", outerStart: i, start: i + 3, end: j - 1, text: src.slice(i + 3, j - 1) });
			return j + 1;
		}
	}
	throw new ShellSyntaxError("unterminated arithmetic expansion");
}

/** `$'...'` and `$"..."` are only special outside double quotes. */
function readDollar(src: string, i: number, subs: Sub[], quoted = false): number {
	const next = src[i + 1];
	if (next === "(") return src[i + 2] === "(" ? readArith(src, i, subs) : readParenSub(src, i, i + 2, "command", subs);
	if (quoted && (next === "'" || next === '"')) return i + 1;
	if (next === "'") {
		let j = i + 2;
		while (j < src.length && src[j] !== "'") j += src[j] === "\\" ? 2 : 1;
		if (j >= src.length) throw new ShellSyntaxError("unterminated $'...'");
		return j + 1;
	}
	if (next === '"') return readDouble(src, i + 2, subs);
	if (next === "{") {
		let j = i + 2;
		while (j < src.length && src[j] !== "}") {
			const c = src[j];
			if (c === "\\") j += 2;
			else if (c === "'") j = closeSingle(src, j);
			else if (c === '"') j = readDouble(src, j + 1, subs);
			else if (c === "$") j = readDollar(src, j, subs);
			else if (c === "`") j = readBacktick(src, j, subs);
			else j++;
		}
		if (j >= src.length) throw new ShellSyntaxError("unterminated ${...}");
		return j + 1;
	}
	return i + 1;
}

function readWord(src: string, start: number): Word {
	const subs: Sub[] = [];
	let i = start;
	while (i < src.length) {
		const c = src[i];
		if (c === " " || c === "\t" || c === "\n" || c === "\r") break;
		if (c === "\\") i += 2;
		else if (c === "'") i = closeSingle(src, i);
		else if (c === '"') i = readDouble(src, i + 1, subs);
		else if (c === "`") i = readBacktick(src, i, subs);
		else if (c === "$") i = readDollar(src, i, subs);
		else if ((c === "<" || c === ">") && src[i + 1] === "(") i = readParenSub(src, i, i + 2, "process", subs);
		else if (c === "(" && /^[A-Za-z_][A-Za-z0-9_]*\+?=$/.test(src.slice(start, i))) i = lex(src, i + 1, true).end + 1;
		else if (";&|()<>".includes(c)) break;
		else i++;
	}
	const end = Math.min(i, src.length);
	return { text: src.slice(start, end), start, end, subs };
}

function readHeredocBodies(src: string, i: number, docs: Heredoc[]): number {
	for (const doc of docs) {
		doc.bodyStart = i;
		doc.bodyEnd = src.length;
		while (i < src.length) {
			const nl = src.indexOf("\n", i);
			const lineEnd = nl < 0 ? src.length : nl;
			let line = src.slice(i, lineEnd).replace(/\r$/, "");
			if (doc.stripTabs) line = line.replace(/^\t+/, "");
			const next = nl < 0 ? src.length : nl + 1;
			if (line === doc.delimiter) {
				doc.bodyEnd = i;
				i = next;
				break;
			}
			i = next;
		}
	}
	return i;
}

/**
 * Tokenize from `pos`. With `untilParen`, stop at the `)` that closes a
 * `$(` / `<(` body and return its offset as `end`.
 */
function lex(src: string, pos: number, untilParen: boolean): { tokens: Token[]; end: number } {
	const tokens: Token[] = [];
	const pending: Heredoc[] = [];
	const caseDepths: number[] = [];
	let depth = 0;
	let commandStart = true;
	let i = pos;
	while (i < src.length) {
		const c = src[i];
		if (c === " " || c === "\t" || c === "\r") {
			i++;
			continue;
		}
		if (c === "\\" && src[i + 1] === "\n") {
			i += 2;
			continue;
		}
		if (c === "\n") {
			tokens.push({ kind: "newline", start: i, end: i + 1 });
			i = readHeredocBodies(src, i + 1, pending.splice(0));
			commandStart = true;
			continue;
		}
		if (c === "#") {
			while (i < src.length && src[i] !== "\n") i++;
			continue;
		}
		if (!((c === "<" || c === ">") && src[i + 1] === "(")) {
			REDIRECT.lastIndex = i;
			const redirect = isRedirectStart(c) ? REDIRECT.exec(src) : null;
			if (redirect) {
				const opStart = i;
				const op = redirect[2];
				i += redirect[0].length;
				while (src[i] === " " || src[i] === "\t" || (src[i] === "\\" && src[i + 1] === "\n")) i += src[i] === "\\" ? 2 : 1;
				const target = readWord(src, i);
				if (target.end === i) throw new ShellSyntaxError(`missing target for ${op}`);
				i = target.end;
				let heredoc: Heredoc | undefined;
				if (op === "<<" || op === "<<-") {
					heredoc = {
						delimiter: target.text.replace(/['"\\]/g, ""),
						quoted: /['"\\]/.test(target.text),
						stripTabs: op === "<<-",
						bodyStart: -1,
						bodyEnd: -1,
					};
					pending.push(heredoc);
				}
				tokens.push({ kind: "redirect", redirect: { op, target, heredoc }, start: opStart, end: i });
				continue;
			}
			const op = operatorAt(src, i);
			if (op) {
				if (untilParen && op === "(") depth++;
				if (untilParen && op === ")" && caseDepths.at(-1) !== depth) {
					if (depth === 0) return { tokens, end: i };
					depth--;
				}
				tokens.push({ kind: "op", op, start: i, end: i + op.length });
				i += op.length;
				commandStart = true;
				continue;
			}
		}
		const word = readWord(src, i);
		if (word.end === i) throw new ShellSyntaxError(`unexpected '${c}'`);
		tokens.push({ kind: "word", word, start: word.start, end: word.end });
		if (commandStart) {
			if (word.text === "case") caseDepths.push(depth);
			else if (word.text === "esac") caseDepths.pop();
			commandStart = KEEPS_COMMAND_START.has(word.text);
		}
		i = word.end;
	}
	if (untilParen) throw new ShellSyntaxError("unterminated substitution");
	for (const doc of pending) doc.bodyStart = doc.bodyEnd = src.length;
	tokens.push({ kind: "eof", start: src.length, end: src.length });
	return { tokens, end: src.length };
}

// ---------------------------------------------------------------- parser

class Parser {
	private i = 0;
	private readonly tokens: Token[];

	constructor(tokens: Token[]) {
		this.tokens = tokens;
	}

	private peek(offset = 0): Token {
		return this.tokens[Math.min(this.i + offset, this.tokens.length - 1)];
	}

	private isOp(op: string, offset = 0): boolean {
		const t = this.peek(offset);
		return t.kind === "op" && t.op === op;
	}

	private isWord(text: string): boolean {
		const t = this.peek();
		return t.kind === "word" && t.word.text === text;
	}

	private skipNewlines(): void {
		while (this.peek().kind === "newline") this.i++;
	}

	private expectWord(text: string): void {
		if (!this.isWord(text)) throw new ShellSyntaxError(`expected '${text}'`);
		this.i++;
	}

	private expectOp(op: string): void {
		if (!this.isOp(op)) throw new ShellSyntaxError(`expected '${op}'`);
		this.i++;
	}

	private takeWord(): Word {
		const t = this.peek();
		if (t.kind !== "word") throw new ShellSyntaxError("expected a word");
		this.i++;
		return t.word;
	}

	parseScript(): List {
		const list = this.parseList([]);
		if (this.peek().kind !== "eof") throw new ShellSyntaxError("unexpected token");
		return list;
	}

	private parseList(stops: string[]): List {
		const items: List = [];
		for (;;) {
			this.skipNewlines();
			const t = this.peek();
			if (t.kind === "eof") break;
			if (t.kind === "op" && LIST_END_OPS.has(t.op)) break;
			if (t.kind === "word" && stops.includes(t.word.text)) break;
			const andOr = this.parseAndOr();
			const sep = this.peek();
			if (sep.kind === "op" && (sep.op === ";" || sep.op === "&")) {
				this.i++;
				items.push({ andOr, background: sep.op === "&" });
				continue;
			}
			items.push({ andOr, background: false });
			if (sep.kind !== "newline") break;
		}
		return items;
	}

	private parseAndOr(): AndOr {
		const first = this.parsePipeline();
		const rest: AndOr["rest"] = [];
		while (this.isOp("&&") || this.isOp("||")) {
			const op = (this.peek() as { op: "&&" | "||" }).op;
			this.i++;
			this.skipNewlines();
			rest.push({ op, pipeline: this.parsePipeline() });
		}
		return { first, rest };
	}

	private parsePipeline(): Pipeline {
		let negated = false;
		while (this.isWord("!")) {
			this.i++;
			negated = !negated;
		}
		const commands = [this.parseCommand()];
		while (this.isOp("|") || this.isOp("|&")) {
			this.i++;
			this.skipNewlines();
			commands.push(this.parseCommand());
		}
		return { negated, commands };
	}

	private parseRedirects(): Redirect[] {
		const redirects: Redirect[] = [];
		for (let t = this.peek(); t.kind === "redirect"; t = this.peek()) {
			redirects.push(t.redirect);
			this.i++;
		}
		return redirects;
	}

	private parseCommand(): Command {
		const t = this.peek();
		if (t.kind === "op" && t.op === "(") {
			this.i++;
			const body = this.parseList([]);
			this.expectOp(")");
			return { type: "subshell", body, redirects: this.parseRedirects() };
		}
		if (t.kind === "word") {
			const text = t.word.text;
			if (MISPLACED_WORDS.has(text)) throw new ShellSyntaxError(`unexpected '${text}'`);
			if (text === "{") {
				this.i++;
				const body = this.parseList(["}"]);
				this.expectWord("}");
				return { type: "group", body, redirects: this.parseRedirects() };
			}
			if (text === "if") return this.parseIf();
			if (text === "while" || text === "until") {
				this.i++;
				const cond = this.parseList(["do"]);
				this.expectWord("do");
				const body = this.parseList(["done"]);
				this.expectWord("done");
				return { type: "while", cond, body, redirects: this.parseRedirects() };
			}
			if (text === "for" || text === "select") return this.parseFor();
			if (text === "case") return this.parseCase();
			if (text === "function") {
				this.i++;
				const name = this.takeWord().text;
				if (this.isOp("(")) {
					this.i++;
					this.expectOp(")");
				}
				this.skipNewlines();
				return { type: "function", name, body: this.parseCommand() };
			}
			// bash accepts almost any plain word as a function name, e.g. `:` in a fork bomb.
			if (/^[^\s$`'"\\=]+$/.test(text) && this.isOp("(", 1) && this.isOp(")", 2)) {
				this.i += 3;
				this.skipNewlines();
				return { type: "function", name: text, body: this.parseCommand() };
			}
		}
		return this.parseSimple();
	}

	private parseSimple(): Command {
		const words: Word[] = [];
		const redirects: Redirect[] = [];
		let start = -1;
		let end = -1;
		for (;;) {
			const t = this.peek();
			if (t.kind === "word") words.push(t.word);
			else if (t.kind === "redirect") redirects.push(t.redirect);
			else break;
			if (start < 0) start = t.start;
			end = t.end;
			this.i++;
		}
		if (start < 0) throw new ShellSyntaxError(`unexpected ${this.peek().kind}`);
		return { type: "simple", words, redirects, start, end };
	}

	private parseIf(): Command {
		this.i++;
		const clauses: Array<{ cond: List; body: List }> = [];
		for (;;) {
			const cond = this.parseList(["then"]);
			this.expectWord("then");
			clauses.push({ cond, body: this.parseList(["elif", "else", "fi"]) });
			if (!this.isWord("elif")) break;
			this.i++;
		}
		let elseBody: List | null = null;
		if (this.isWord("else")) {
			this.i++;
			elseBody = this.parseList(["fi"]);
		}
		this.expectWord("fi");
		return { type: "if", clauses, elseBody, redirects: this.parseRedirects() };
	}

	private parseFor(): Command {
		this.i++;
		if (this.isOp("(")) throw new ShellSyntaxError("arithmetic for loops are not supported");
		const name = this.takeWord().text;
		this.skipNewlines();
		let words: Word[] | null = null;
		if (this.isWord("in")) {
			this.i++;
			words = [];
			for (let t = this.peek(); t.kind === "word"; t = this.peek()) {
				words.push(t.word);
				this.i++;
			}
		}
		if (this.isOp(";")) this.i++;
		this.skipNewlines();
		this.expectWord("do");
		const body = this.parseList(["done"]);
		this.expectWord("done");
		return { type: "for", name, words, body, redirects: this.parseRedirects() };
	}

	private parseCase(): Command {
		this.i++;
		const subject = this.takeWord();
		this.skipNewlines();
		this.expectWord("in");
		const items: Array<{ patterns: Word[]; body: List }> = [];
		for (;;) {
			this.skipNewlines();
			if (this.isWord("esac")) {
				this.i++;
				break;
			}
			if (this.isOp("(")) this.i++;
			const patterns = [this.takeWord()];
			while (this.isOp("|")) {
				this.i++;
				patterns.push(this.takeWord());
			}
			this.expectOp(")");
			items.push({ patterns, body: this.parseList(["esac"]) });
			if (this.isOp(";;") || this.isOp(";&") || this.isOp(";;&")) this.i++;
			else if (!this.isWord("esac")) throw new ShellSyntaxError("expected ';;' or 'esac'");
		}
		return { type: "case", subject, items, redirects: this.parseRedirects() };
	}
}

/** Parse a bash script. Throws ShellSyntaxError on anything unsupported. */
export function parseScript(src: string): List {
	return new Parser(lex(src, 0, false).tokens).parseScript();
}
