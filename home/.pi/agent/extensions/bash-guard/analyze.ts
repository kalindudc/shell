/**
 * Bash guard policy. No dependencies beyond node:fs.
 *
 * Threat model: catch agent mistakes (rm -rf in the wrong place, writes to
 * system paths), not adversarial obfuscation.
 *
 * Scratch paths (/tmp and /private/tmp) are ignored completely: anything that
 * provably only touches them is allowed. To prove it, the command is parsed
 * (shell.ts) and evaluated with a small model of the shell's state:
 *
 * - the working directory, starting at the session cwd and following `cd`
 *   only where the cd must have succeeded (`&&`, `|| exit`, `set -e`);
 * - variables: assignments in the command (including `$(mktemp ... /tmp/...)`)
 *   and, for names the command never assigns, the environment pi passes on;
 * - subshells, pipelines, conditionals, loops and traps, merging every value a
 *   variable or the cwd could hold at each point;
 * - symlinks, by resolving operand paths on disk, so /tmp/link/ -> ~/repo is
 *   not treated as scratch.
 *
 * rm/mv/chmod/chown are judged precisely from their resolved operands. Every
 * other command the analysis cannot account for (quoted code passed to ssh,
 * python heredocs, unparseable input, ...) keeps the original conservative
 * text patterns, so nothing outside /tmp is relaxed.
 */

import { realpathSync, statSync } from "node:fs";
import { type AndOr, type Command, type List, type Pipeline, type Redirect, type SimpleCommand, type Word, ShellSyntaxError, parseScript } from "./shell.ts";

export type Severity = "critical" | "high";

export interface Finding {
	severity: Severity;
	kind: "risk" | "path";
	detail: string;
}

export interface Analysis {
	findings: Finding[];
	maxSeverity: Severity | "safe";
	/** False when the command could not be parsed and only text patterns were applied. */
	parsed: boolean;
	/** Set when the analyzer itself failed (a bug), not for shell syntax errors. */
	error?: string;
}

export type Env = Readonly<Record<string, string | undefined>>;

/** Scratch directories the agent may freely create, modify, and delete. */
export const scratchRoots = ["/tmp", "/private/tmp"];

/** System paths that stay auto-blocked for rm/mv/chmod/chown. */
export const protectedPaths = ["/", "/bin", "/boot", "/dev", "/etc", "/lib", "/private/etc", "/proc", "/root", "/sbin", "/sys", "/usr"];

const SAFE_DEVICES = /^\/dev\/(null|zero|random|urandom|tty|stdin|stdout|stderr|fd\/\d+)$/;
const RM_RF = "Recursive force delete (rm -rf)";
const SUDO_RM = "Elevated delete operation";

/**
 * Applied, one command at a time, to whatever the precise analysis could not
 * account for (rm -rf is checked by textualRmRf). Quantifiers are bounded so
 * long opaque text cannot trigger quadratic backtracking.
 */
const TEXT_RISKS: Array<{ pattern: RegExp; severity: Severity; detail: string }> = [
	{ pattern: /\b(mkfs\.|dd\s.{0,256}?of=\/dev\/)/i, severity: "critical", detail: "Disk formatting or raw device write" },
	{
		pattern: /(^|[;&]\s*|\|\|?\s*|&&\s*)(sudo\s+)?(shutdown|reboot|halt|poweroff)\b/im,
		severity: "critical",
		detail: "System shutdown/reboot",
	},
	{ pattern: /\bsudo\s+rm\b/i, severity: "high", detail: SUDO_RM },
	{ pattern: /\bsudo\s.{0,256}?(>|tee)\s*\/etc\//i, severity: "high", detail: "Writing to /etc with sudo" },
	{
		pattern: /\b(systemctl\s+(stop|disable|mask)|service\s+\S+\s+(stop|disable|mask))/i,
		severity: "high",
		detail: "Stopping or disabling system service",
	},
];
/** `:(){ :|:& };:` and spacing variants. Spans several commands, so it is matched against whole scripts. */
const FORK_BOMB = /:\(\)\s*\{\s*:\s*\|\s*:\s*&?\s*;?\s*\}\s*;\s*:/;
/** rm/mv/chmod/chown as a command word inside opaque text (not `--rm`, not `/tmp/rm.txt`). */
const TEXT_PATH_COMMAND = /(^|[^\w./-])(rm|mv|chmod|chown)(\s|$)/m;

const OWNED = new Set(["rm", "mv", "chmod", "chown"]);
const SHELLS = new Set(["bash", "sh", "zsh", "dash", "ksh"]);
const NUMERIC_VARS = new Set(["$", "!", "?", "#", "RANDOM", "SECONDS", "LINENO", "BASHPID", "PPID", "UID", "EUID", "EPOCHSECONDS"]);
/** Variables bash sets itself, so the inherited environment says nothing about them. */
const SHELL_VARS = new Set(["OLDPWD", "_", "IFS", "REPLY", "OPTARG", "OPTIND", "SHLVL", "PIPESTATUS", "HOSTNAME", "HOSTTYPE", "OSTYPE", "MACHTYPE", "BASH", "BASHOPTS", "SHELLOPTS"]);
const ASSIGN = /^([A-Za-z_][A-Za-z0-9_]*)(\[[^\]]*\])?(\+?)=/;
/** Command wrappers and the options of theirs that take a separate argument. */
const WRAPPERS = new Map<string, string[]>([
	["sudo", ["-u", "-g", "-h", "-p", "-C", "-D", "-r", "-t", "-U", "-T", "-R"]],
	["doas", ["-u", "-C"]],
	["env", ["-u", "-C", "-S", "-P"]],
	["command", []],
	["builtin", []],
	["exec", ["-a"]],
	["nohup", []],
	["nice", ["-n"]],
	["time", []],
	["timeout", ["-s", "-k"]],
	["stdbuf", ["-i", "-o", "-e"]],
	["xargs", ["-I", "-L", "-n", "-P", "-s", "-d", "-E", "-a"]],
	["caffeinate", ["-t", "-w"]],
	["chronic", []],
	["unbuffer", []],
	["ionice", ["-c", "-n", "-p"]],
]);

/**
 * Every finding needs one of these words in the text (owned commands, sudo,
 * text patterns), so commands without them skip analysis. This runs on every
 * bash call and lets ~94% of real agent commands through without parsing.
 */
const KEYWORDS = /\b(rm|mv|chmod|chown|mkfs|dd|shutdown|reboot|halt|poweroff|sudo|doas|systemctl|service)\b|:\(\)/;

/** Most values a variable or the cwd may hold before it is treated as unknown. */
const CAP = 16;
const MAX_DEPTH = 6;
const MAX_TRAPS = 16;
/** Bounds on work per command; past them only the text patterns apply. */
const MAX_EVALS = 10_000;
const MAX_LENGTH = 256 * 1024;
/** Assignments kept in a Vars delta before it is folded into a new base. */
const DELTA_LIMIT = 32;

class BudgetExceeded extends Error {}

// ---------------------------------------------------------------- paths

/** Resolve . and .. segments textually so "/tmp/../etc" is not mistaken for /tmp. */
export function normalizePath(path: string): string {
	const absolute = path.startsWith("/");
	const resolved: string[] = [];
	for (const segment of path.split("/")) {
		if (segment === "" || segment === ".") continue;
		if (segment === "..") resolved.pop();
		else resolved.push(segment);
	}
	return (absolute ? "/" : "") + resolved.join("/");
}

function isUnder(path: string, roots: string[]): boolean {
	return roots.some((root) => path === root || path.startsWith(`${root}/`));
}

/** realpath results for the command being analyzed; cleared per command because the filesystem changes. */
const realCache = new Map<string, string>();

/** realpath of an existing path, or null. Checks existence first: a thrown ENOENT costs far more than a stat. */
function realIfExists(path: string): string | null {
	try {
		return statSync(path, { throwIfNoEntry: false }) ? realpathSync.native(path) : null;
	} catch {
		return null;
	}
}

/** Physical path of `dir`; missing components are appended as written. */
function realDir(dir: string): string {
	const cached = realCache.get(dir);
	if (cached !== undefined) return cached;
	let real = realIfExists(dir);
	if (real === null) {
		const slash = dir.lastIndexOf("/");
		if (slash < 0 || dir === "/") real = dir;
		else {
			const parent = realDir(dir.slice(0, slash) || "/");
			real = parent === "/" ? `/${dir.slice(slash + 1)}` : `${parent}/${dir.slice(slash + 1)}`;
		}
	}
	realCache.set(dir, real);
	return real;
}

/**
 * Resolve absolute `path` the way the kernel would, following symlinks in its
 * directories. The final component is only followed when `followLast` is set
 * or the path ends in "/", "." or "..", matching how rm treats a symlink
 * operand. Returns null for globs in directory components.
 */
function physicalPath(path: string, followLast: boolean): string | null {
	const trimmed = path.replace(/\/+$/, "") || "/";
	const follow = followLast || trimmed !== path || /(^|\/)\.\.?$/.test(trimmed);
	const slash = trimmed.lastIndexOf("/");
	const dir = follow ? trimmed : trimmed.slice(0, slash) || "/";
	if (/[*?[]/.test(dir)) return null;
	const real = realDir(dir);
	if (follow) return real;
	const base = trimmed.slice(slash + 1);
	return real === "/" ? `/${base}` : `${real}/${base}`;
}

function scratchPath(path: string): boolean {
	if (!isUnder(normalizePath(path), scratchRoots)) return false;
	const physical = physicalPath(path, false);
	return physical !== null && isUnder(normalizePath(physical), scratchRoots);
}

/** True when `path` (absolute) is inside a scratch root, both textually and on disk. */
export function isScratchPath(path: string): boolean {
	try {
		return scratchPath(path);
	} finally {
		realCache.clear();
	}
}

function protectedIn(path: string): string | null {
	const normalized = normalizePath(path);
	if (isUnder(normalized, scratchRoots)) return null;
	return protectedPaths.find((r) => (r === "/" ? normalized === "/" : isUnder(normalized, [r]))) ?? null;
}

/**
 * The protected root `path` falls under. Symlinks are only resolved for paths
 * that look like scratch, where the operation would otherwise be allowed;
 * everything else is judged as written, so most operands cost no syscalls.
 */
function protectedRoot(path: string, followLast: boolean): string | null {
	if (!isUnder(normalizePath(path), scratchRoots)) return protectedIn(path);
	for (const physical of [physicalPath(path, false), followLast ? physicalPath(path, true) : null]) {
		const root = physical === null ? null : protectedIn(physical);
		if (root) return root;
	}
	return null;
}

// ---------------------------------------------------------------- state

type Val = ReadonlySet<string> | null;

/** A shell function body and the script text its offsets refer to. */
interface FunctionDef {
	body: Command;
	src: string;
}

const NO_FUNCS: ReadonlyMap<string, FunctionDef> = new Map();

const NO_VARS: ReadonlyMap<string, Val> = new Map();

/**
 * Persistent variable map: a shared base plus a small delta. An assignment
 * copies at most DELTA_LIMIT entries instead of every variable, and states
 * that share a base merge and compare by their deltas alone.
 */
class Vars {
	static readonly EMPTY = new Vars(NO_VARS, NO_VARS);
	readonly base: ReadonlyMap<string, Val>;
	readonly delta: ReadonlyMap<string, Val>;

	constructor(base: ReadonlyMap<string, Val>, delta: ReadonlyMap<string, Val>) {
		this.base = base;
		this.delta = delta;
	}

	/** The entry for `name` (null when unknown), or undefined when never assigned. */
	get(name: string): Val | undefined {
		const own = this.delta.get(name);
		return own !== undefined ? own : this.base.get(name);
	}

	has(name: string): boolean {
		return this.delta.has(name) || this.base.has(name);
	}

	set(name: string, value: Val): Vars {
		const delta = new Map(this.delta).set(name, value);
		if (delta.size <= DELTA_LIMIT) return new Vars(this.base, delta);
		const base = new Map(this.base);
		for (const [k, v] of delta) base.set(k, v);
		return new Vars(base, NO_VARS);
	}

	forEach(fn: (value: Val, name: string) => void): void {
		for (const [name, value] of this.base) if (!this.delta.has(name)) fn(value, name);
		for (const [name, value] of this.delta) fn(value, name);
	}
}

interface State {
	/** Possible working directories; null when unknown. */
	cwd: Val;
	/** Variables the command assigned; a null value means unknown. */
	vars: Vars;
	/** Environment inherited from pi, for variables not in `vars`; null once unknown. */
	env: Env | null;
	errexit: boolean;
	funcs: ReadonlyMap<string, FunctionDef>;
}

interface Outcome {
	/** State when the command succeeded, or null when that cannot happen. */
	ok: State | null;
	fail: State | null;
	/** `set -e` does not apply (negated pipelines). */
	noErrexit?: boolean;
}

interface TrapRecord {
	text: string;
	state: State;
	/** Index into Ctx.events when the trap was set. */
	event: number;
	inLoop: boolean;
}

interface Ctx {
	src: string;
	findings: Finding[];
	/** Text of commands the analysis could not account for, matched one at a time. */
	units: string[];
	/** Whole scripts with accounted-for parts blanked, for patterns spanning commands. */
	wholes: string[];
	/** Spans of `src` that become units. */
	spans: Array<[number, number]>;
	/** Spans of `src` accounted for and blanked from the fallback text. */
	blanks: Array<[number, number]>;
	/** Names (or "*cwd*", "*all*") changed, in evaluation order. */
	events: string[];
	traps: TrapRecord[];
	/** States at `exit` and `set -e` exits of the top-level script. */
	exits: State[];
	/** Functions being called, innermost last, to stop recursion. */
	calls: ReadonlySet<string>;
	/** Functions called anywhere; the others are checked once at the end. */
	called: Set<string>;
	funcDefs: Array<{ name: string; def: FunctionDef; state: State }>;
	/** States at `return` inside the function being called, or null outside functions. */
	returns: State[] | null;
	depth: number;
	/** Exploring a loop body: only track state, check and record nothing. */
	dry: boolean;
	/** Commands left to evaluate before giving up on the precise analysis. */
	budget: { left: number };
	inLoop: boolean;
	inCondition: boolean;
	inSubstitution: boolean;
	elevated: boolean;
}

function one(value: string): ReadonlySet<string> {
	return new Set([value]);
}

function mergeVal(a: Val, b: Val): Val {
	if (!a || !b) return null;
	if (a === b) return a;
	const merged = new Set([...a, ...b]);
	return merged.size > CAP ? null : merged;
}

function sameVal(a: Val, b: Val): boolean {
	if (a === b) return true;
	if (!a || !b || a.size !== b.size) return false;
	for (const v of a) if (!b.has(v)) return false;
	return true;
}

const ZERO = one("0");
/** Values of inherited variables for the command being analyzed (its env is fixed). */
const envCache = new Map<string, Val>();

function getVar(st: State, name: string): Val {
	if (name === "PWD") return st.cwd;
	if (NUMERIC_VARS.has(name)) return ZERO;
	const own = st.vars.get(name);
	if (own !== undefined) return own;
	if (!st.env || SHELL_VARS.has(name) || name.startsWith("BASH_")) return null;
	let inherited = envCache.get(name);
	if (inherited === undefined) {
		inherited = one(st.env[name] ?? "");
		envCache.set(name, inherited);
	}
	return inherited;
}

/** The value `name` has in `st`, given its entry `own` in `st.vars` (undefined when absent). */
function valueIn(st: State, name: string, own: Val | undefined): Val {
	return own !== undefined ? own : getVar(st, name);
}

/** States mostly share their variables, so work on deltas and compare by reference before by value. */
function mergeVars(a: State, b: State): Vars {
	const av = a.vars;
	const bv = b.vars;
	if (av === bv) return av;
	const out = new Map<string, Val>();
	const merge = (name: string, x: Val | undefined, y: Val | undefined): void => {
		out.set(name, x === y && x !== undefined ? x : mergeVal(valueIn(a, name, x), valueIn(b, name, y)));
	};
	if (av.base === bv.base) {
		for (const [name, x] of av.delta) merge(name, x, bv.get(name));
		for (const [name, y] of bv.delta) if (!av.delta.has(name)) merge(name, av.get(name), y);
		return new Vars(av.base, out);
	}
	av.forEach((x, name) => merge(name, x, bv.get(name)));
	bv.forEach((y, name) => {
		if (!av.has(name)) merge(name, undefined, y);
	});
	return new Vars(out, NO_VARS);
}

function sameVars(a: State, b: State): boolean {
	const av = a.vars;
	const bv = b.vars;
	if (av === bv) return true;
	const same = (name: string, x: Val | undefined, y: Val | undefined): boolean =>
		(x === y && x !== undefined) || sameVal(valueIn(a, name, x), valueIn(b, name, y));
	if (av.base === bv.base) {
		for (const [name, x] of av.delta) if (!same(name, x, bv.get(name))) return false;
		for (const [name, y] of bv.delta) if (!av.delta.has(name) && !same(name, av.get(name), y)) return false;
		return true;
	}
	let equal = true;
	av.forEach((x, name) => {
		if (equal && !same(name, x, bv.get(name))) equal = false;
	});
	bv.forEach((y, name) => {
		if (equal && !av.has(name) && !same(name, undefined, y)) equal = false;
	});
	return equal;
}

function mergeState(a: State | null, b: State | null): State | null {
	if (!a) return b;
	if (!b || a === b) return a;
	return {
		cwd: mergeVal(a.cwd, b.cwd),
		vars: mergeVars(a, b),
		env: a.env === b.env ? a.env : null,
		errexit: a.errexit && b.errexit,
		funcs: a.funcs === b.funcs || !b.funcs.size ? a.funcs : new Map([...b.funcs, ...a.funcs]),
	};
}

function sameState(a: State, b: State): boolean {
	return a === b || (a.errexit === b.errexit && a.env === b.env && sameVal(a.cwd, b.cwd) && sameVars(a, b));
}

function setVar(st: State, name: string, value: Val): State {
	return { ...st, vars: st.vars.set(name, value) };
}

function withCwd(st: State, cwd: Val): State {
	return { ...st, cwd };
}

/** After `source`, `eval <unknown>` or calling a shell function. */
function forgetAll(st: State): State {
	return { ...st, cwd: null, vars: Vars.EMPTY, env: null };
}

/** A child shell sees the environment, but we do not know which of our assignments were exported. */
function childState(st: State, errexit: boolean): State {
	const unknown = new Map<string, Val>();
	st.vars.forEach((_, name) => unknown.set(name, null));
	return { cwd: st.cwd, vars: new Vars(unknown, NO_VARS), env: st.env, errexit, funcs: NO_FUNCS };
}

function both(st: State | null): Outcome {
	return { ok: st, fail: st };
}

function report(ctx: Ctx, severity: Severity, kind: Finding["kind"], detail: string): void {
	if (!ctx.dry) ctx.findings.push({ severity, kind, detail });
}

function blank(ctx: Ctx, start: number, end: number): void {
	if (!ctx.dry) ctx.blanks.push([start, end]);
}

function keep(ctx: Ctx, start: number, end: number): void {
	if (!ctx.dry) ctx.spans.push([start, end]);
}

function opaque(ctx: Ctx, text: string): void {
	if (ctx.dry) return;
	ctx.units.push(text);
	ctx.wholes.push(text);
}

/** Replace the given spans with spaces, keeping newlines so offsets and lines stay put. */
function blankOut(text: string, blanks: Array<[number, number]>): string {
	if (!blanks.length) return text;
	blanks.sort((a, b) => a[0] - b[0]);
	let out = "";
	let pos = 0;
	for (const [s, e] of blanks) {
		const start = Math.max(s, pos);
		const end = Math.min(e, text.length);
		if (end <= start) continue;
		out += text.slice(pos, start) + text.slice(start, end).replace(/[^\n]/g, " ");
		pos = end;
	}
	return out + text.slice(pos);
}

/** Hand the unaccounted parts of a finished script to the text fallback. */
function finish(ctx: Ctx): void {
	if (ctx.dry) return;
	const whole = blankOut(ctx.src, ctx.blanks);
	ctx.wholes.push(whole);
	for (const [start, end] of ctx.spans) ctx.units.push(whole.slice(start, end));
}

// ---------------------------------------------------------------- expansion

interface ExpandOpts {
	/** Assignment value: no word splitting, brace or tilde expansion. */
	assignment?: boolean;
	/** Keep whitespace from unquoted expansions (eval, trap, bash -c strings). */
	noSplit?: boolean;
	/** Model the failure path of `$(mktemp ...)`: it expands to "". */
	substFails?: boolean;
}

/** Parsed scripts for the command being analyzed (loop passes and traps re-read the same text). */
const parseCache = new Map<string, List | null>();

function cachedParse(text: string): List | null {
	let list = parseCache.get(text);
	if (list === undefined) {
		try {
			list = parseScript(text);
		} catch (error) {
			if (!(error instanceof ShellSyntaxError)) throw error;
			list = null;
		}
		parseCache.set(text, list);
	}
	return list;
}

/** The path `$(mktemp ...)` creates, null when unknown, undefined when `body` is not mktemp. */
function mktempValue(body: string, st: State): Val | undefined {
	if (!/^\s*mktemp\s/.test(body)) return undefined;
	const list = cachedParse(body);
	if (!list || list.length !== 1 || list[0].background || list[0].andOr.rest.length) return undefined;
	const pipeline = list[0].andOr.first;
	const cmd = pipeline.commands[0];
	if (pipeline.negated || pipeline.commands.length !== 1 || cmd.type !== "simple" || !cmd.words.length) return undefined;
	const argv = cmd.words.map((w) => literalOf(w, st));
	if (argv[0] !== "mktemp") return undefined;
	let dir: string | null | undefined;
	let template: string | undefined;
	for (let k = 1; k < argv.length; k++) {
		const arg = argv[k];
		if (arg === null) return null;
		if (arg === "-p") dir = argv[++k] ?? null;
		else if (arg.startsWith("--tmpdir=")) dir = arg.slice("--tmpdir=".length);
		else if (arg === "--tmpdir" || arg === "-t") return null;
		else if (/^-[a-zA-Z]+$/.test(arg)) {
			if (/[tp]/.test(arg)) return null;
		} else if (!arg.startsWith("--")) template = arg;
	}
	if (dir === null || dir === "") return null;
	const path = dir === undefined ? template : `${dir}/${template ?? "tmp.XXXXXXXXXX"}`;
	if (path === undefined || !path.includes("/")) return null;
	if (path.startsWith("/")) return one(path);
	return st.cwd ? new Set([...st.cwd].map((c) => `${c}/${path}`)) : null;
}

function unescapeBacktick(text: string): string {
	return text.replace(/\\([`\\$])/g, "$1");
}

/** `${NAME}`, `${#NAME}`, `${NAME:-default}` and `${NAME-default}` with a literal default. */
function braceVar(inner: string, st: State): Val {
	if (/^#[A-Za-z_]\w*$/.test(inner)) return one("0");
	if (/^([A-Za-z_]\w*|[$!?#])$/.test(inner)) return getVar(st, inner);
	const m = /^([A-Za-z_]\w*)(:?-)([^$`'"\\{}]*)$/.exec(inner);
	if (!m) return null;
	const values = getVar(st, m[1]);
	if (!values) return null;
	return new Set([...values].map((v) => (v === "" ? m[3] : v)));
}

/** One `$...`, backtick or process substitution starting at text[i]. */
function expansion(word: Word, text: string, base: number, i: number, st: State, opts: ExpandOpts, quoted: boolean): { values: Val; end: number } {
	const c = text[i];
	const next = text[i + 1];
	if (c === "`" || c === "<" || c === ">" || next === "(") {
		const sub = word.subs.find((s) => s.outerStart === base + i);
		if (!sub) return { values: null, end: text.length };
		const end = sub.end - base + (sub.kind === "arith" ? 2 : 1);
		if (sub.kind === "arith") return { values: one("0"), end };
		if (sub.kind === "process") return { values: one("/dev/fd/63"), end };
		const made = mktempValue(sub.kind === "backtick" ? unescapeBacktick(sub.text) : sub.text, st);
		if (made === undefined) return { values: null, end };
		return { values: opts.substFails ? one("") : made, end };
	}
	if (next === "'" && !quoted) {
		const close = text.indexOf("'", i + 2);
		const inner = text.slice(i + 2, close);
		return { values: inner.includes("\\") ? null : one(inner), end: close + 1 };
	}
	if (next === '"' && !quoted) return { values: one(""), end: i + 1 };
	if (next === "{") {
		const close = text.indexOf("}", i + 2);
		return { values: braceVar(text.slice(i + 2, close), st), end: close + 1 };
	}
	const name = /^([A-Za-z_]\w*|[$!?#])/.exec(text.slice(i + 1));
	if (name) return { values: getVar(st, name[1]), end: i + 1 + name[1].length };
	if (next !== undefined && /[0-9@*-]/.test(next)) return { values: null, end: i + 2 };
	return { values: one("$"), end: i + 1 };
}

/** Options of an unquoted `{a,b}` brace expansion; undefined when `{` is literal, null when unsupported. */
function braceOptions(text: string, i: number): { options: string[]; end: number } | null | undefined {
	const close = text.indexOf("}", i + 1);
	if (close < 0) return undefined;
	const inner = text.slice(i + 1, close);
	if (/[{$`'"\\]/.test(inner)) return null;
	if (inner.includes(",")) return { options: inner.split(","), end: close + 1 };
	return inner.includes("..") ? null : undefined;
}

/**
 * Every string `text` (a word, or the tail of one starting at `base`) can
 * expand to, after quote removal. Null when any part is unknown.
 */
function expandText(word: Word, text: string, base: number, st: State, opts: ExpandOpts): Val {
	let alts = [""];
	let pending = "";
	const literal = (s: string): void => {
		pending += s;
	};
	const flush = (): void => {
		if (!pending) return;
		const suffix = pending;
		alts = alts.length === 1 ? [alts[0] + suffix] : alts.map((a) => a + suffix);
		pending = "";
	};
	const product = (values: Iterable<string>): boolean => {
		flush();
		const next: string[] = [];
		for (const a of alts) for (const v of values) next.push(a + v);
		alts = next;
		return next.length <= CAP;
	};
	if (text.startsWith("~")) return null;
	let quoted = false;
	let i = 0;
	while (i < text.length) {
		const c = text[i];
		if (c === '"') {
			quoted = !quoted;
			i++;
			continue;
		}
		if (c === "\\") {
			const escaped = text[i + 1];
			if (escaped !== undefined && escaped !== "\n") literal(quoted && !'$`"\\'.includes(escaped) ? `\\${escaped}` : escaped);
			i += 2;
			continue;
		}
		if (!quoted && c === "'") {
			const close = text.indexOf("'", i + 1);
			literal(text.slice(i + 1, close));
			i = close + 1;
			continue;
		}
		if (c === "$" || c === "`" || (!quoted && (c === "<" || c === ">") && text[i + 1] === "(")) {
			const { values, end } = expansion(word, text, base, i, st, opts, quoted);
			if (!values) return null;
			if (!quoted && !opts.assignment && !opts.noSplit) for (const v of values) if (/\s/.test(v)) return null;
			if (!product(values)) return null;
			i = end;
			continue;
		}
		if (!quoted && !opts.assignment && c === "{") {
			const brace = braceOptions(text, i);
			if (brace === null) return null;
			if (brace) {
				if (!product(brace.options)) return null;
				i = brace.end;
				continue;
			}
		}
		if (!quoted && opts.assignment && c === "~" && text[i - 1] === ":") return null;
		literal(c);
		i++;
	}
	flush();
	return new Set(alts);
}

/** Last expansion of each word; words are expanded repeatedly with the same state. */
const expandCache = new WeakMap<Word, { st: State; noSplit: boolean; value: Val }>();

function expandWord(word: Word, st: State, opts: ExpandOpts = {}): Val {
	const noSplit = opts.noSplit === true;
	const hit = expandCache.get(word);
	if (hit && hit.st === st && hit.noSplit === noSplit) return hit.value;
	const value = expandText(word, word.text, word.start, st, opts);
	expandCache.set(word, { st, noSplit, value });
	return value;
}

function literalOf(word: Word | undefined, st: State): string | null {
	if (!word) return null;
	const values = expandWord(word, st);
	return values && values.size === 1 ? [...values][0] : null;
}

function concat(a: Val, b: Val): Val {
	if (!a || !b) return null;
	const out = new Set<string>();
	for (const x of a) for (const y of b) out.add(x + y);
	return out.size > CAP ? null : out;
}

/** Absolute paths an operand may name, or null when unknown. Empty expansions are skipped. */
function resolvePaths(word: Word, st: State): string[] | null {
	const values = expandWord(word, st);
	if (!values) return null;
	const out: string[] = [];
	for (const v of values) {
		if (v === "") continue;
		if (v.startsWith("/")) out.push(v);
		else if (!st.cwd) return null;
		else for (const c of st.cwd) out.push(`${c}/${v}`);
	}
	return out;
}

/** Literal text before the first expansion or glob, for operands that cannot be resolved. */
function literalPrefix(text: string): string {
	let out = "";
	for (const c of text) {
		if ("$`*?[{~".includes(c)) break;
		if (c !== "'" && c !== '"' && c !== "\\") out += c;
	}
	return out;
}

// ---------------------------------------------------------------- nested code

/**
 * Analyze `text` as a script of its own. With `inert`, text without any
 * keyword is skipped: callers pass it when the script's state does not flow
 * back (substitutions, child shells, traps).
 */
function analyzeNested(text: string, st: State, ctx: Ctx, overrides: Partial<Ctx> = {}, inert = false): { ok: boolean; state: State | null } {
	if (inert && !KEYWORDS.test(text)) return { ok: true, state: st };
	const list = ctx.depth < MAX_DEPTH ? cachedParse(text) : null;
	if (!list) {
		opaque(ctx, text);
		return { ok: false, state: null };
	}
	const child: Ctx = { ...ctx, inCondition: false, ...overrides, src: text, spans: [], blanks: [], depth: ctx.depth + 1 };
	const state = evalList(list, st, child);
	finish(child);
	return { ok: true, state };
}

/** Command substitutions run in a subshell: analyze them, then hide them from the text fallback. */
function analyzeSubs(word: Word, st: State, ctx: Ctx): void {
	if (ctx.dry) return;
	for (const sub of word.subs) {
		if (sub.kind === "arith") opaque(ctx, sub.text);
		else {
			const text = sub.kind === "backtick" ? unescapeBacktick(sub.text) : sub.text;
			analyzeNested(text, { ...st, errexit: false }, ctx, { inSubstitution: true }, true);
		}
		blank(ctx, sub.start, sub.end);
	}
}

function redirectSubs(redirects: Redirect[], st: State, ctx: Ctx): void {
	for (const r of redirects) {
		analyzeSubs(r.target, st, ctx);
		if (r.heredoc) keep(ctx, r.heredoc.bodyStart, r.heredoc.bodyEnd);
	}
}

// ---------------------------------------------------------------- evaluation

function evalList(list: List, st: State, ctx: Ctx): State | null {
	let current: State | null = st;
	let last = st;
	for (const item of list) {
		const out = evalAndOr(item.andOr, current ?? last, ctx);
		if (current && !item.background) current = out;
		if (current) last = current;
	}
	return current;
}

function evalAndOr(andOr: AndOr, st: State, ctx: Ctx): State | null {
	let r = evalPipeline(andOr.first, st, ctx);
	let ok = r.ok;
	let failCur = r.fail;
	let failSkip: State | null = null;
	for (const { op, pipeline } of andOr.rest) {
		if (op === "&&") {
			failSkip = mergeState(failSkip, failCur);
			r = evalPipeline(pipeline, ok ?? st, ctx);
			failCur = ok ? r.fail : null;
			ok = ok ? r.ok : null;
		} else {
			const from = mergeState(failSkip, failCur);
			r = evalPipeline(pipeline, from ?? st, ctx);
			ok = from ? mergeState(ok, r.ok) : ok;
			failCur = from ? r.fail : null;
			failSkip = null;
		}
	}
	// set -e exits only when the last command of the list fails.
	const exits = failCur !== null && failCur.errexit && !ctx.inCondition && !r.noErrexit;
	if (exits && failCur && ctx.depth === 0 && !ctx.dry) ctx.exits.push(failCur);
	return mergeState(mergeState(ok, failSkip), exits ? null : failCur);
}

function evalPipeline(pipeline: Pipeline, st: State, ctx: Ctx): Outcome {
	if (pipeline.commands.length === 1) {
		const r = evalCommand(pipeline.commands[0], st, pipeline.negated ? { ...ctx, inCondition: true } : ctx, false);
		return pipeline.negated ? { ok: r.fail, fail: r.ok, noErrexit: true } : r;
	}
	// Each element runs in a subshell, so none of them change our state.
	pipeline.commands.forEach((cmd, k) => evalCommand(cmd, st, ctx, k < pipeline.commands.length - 1));
	return { ok: st, fail: st, noErrexit: pipeline.negated };
}

/** Run a loop body to a fixpoint so values assigned in later iterations are seen by earlier commands. */
function fixpoint(start: State, ctx: Ctx, step: (x: State, c: Ctx) => State | null): State {
	const loop = { ...ctx, inLoop: true };
	const dry = { ...loop, dry: true };
	let x = start;
	let stable = false;
	for (let k = 0; k < 6 && !stable; k++) {
		const next = mergeState(x, step(x, dry)) ?? x;
		stable = sameState(next, x);
		x = next;
	}
	if (!stable) x = forgetAll(x);
	step(x, loop);
	return x;
}

function expandWords(words: Word[], st: State): Val {
	const out = new Set<string>();
	for (const word of words) {
		const values = expandWord(word, st);
		if (!values) return null;
		for (const v of values) out.add(v);
		if (out.size > CAP) return null;
	}
	return out;
}

/** Record which variables (or the cwd) a command changed, for traps set earlier. */
function noteChanges(ctx: Ctx, before: State, out: Outcome): void {
	if (ctx.dry) return;
	for (const after of [out.ok, out.fail]) {
		if (!after || after === before) continue;
		if (!sameVal(before.cwd, after.cwd)) ctx.events.push("*cwd*");
		if (after.env !== before.env) ctx.events.push("*all*");
		else if (after.vars !== before.vars) {
			// Variables are only ever added or changed, never dropped, while env is unchanged.
			const check = (value: Val, name: string): void => {
				const own = before.vars.get(name);
				if (value !== own && !sameVal(valueIn(before, name, own), value)) ctx.events.push(name);
			};
			if (after.vars.base === before.vars.base) for (const [name, value] of after.vars.delta) check(value, name);
			else after.vars.forEach(check);
		}
	}
}

function evalCommand(cmd: Command, st: State, ctx: Ctx, piped: boolean): Outcome {
	if (--ctx.budget.left < 0) throw new BudgetExceeded();
	const out = evalCommandInner(cmd, st, ctx, piped);
	noteChanges(ctx, st, out);
	return out;
}

function evalCommandInner(cmd: Command, st: State, ctx: Ctx, piped: boolean): Outcome {
	switch (cmd.type) {
		case "simple":
			return evalSimple(cmd, st, ctx, piped);
		case "subshell":
			redirectSubs(cmd.redirects, st, ctx);
			evalList(cmd.body, st, ctx);
			return both(st);
		case "group":
			redirectSubs(cmd.redirects, st, ctx);
			return both(evalList(cmd.body, st, ctx));
		case "if": {
			redirectSubs(cmd.redirects, st, ctx);
			let out: State | null = null;
			let from: State | null = st;
			for (const clause of cmd.clauses) {
				const cond = evalList(clause.cond, from ?? st, { ...ctx, inCondition: true });
				out = mergeState(out, evalList(clause.body, cond ?? st, ctx));
				from = cond;
			}
			return both(mergeState(out, cmd.elseBody ? evalList(cmd.elseBody, from ?? st, ctx) : from));
		}
		case "while":
			redirectSubs(cmd.redirects, st, ctx);
			return both(
				fixpoint(st, ctx, (x, c) => {
					const cond = evalList(cmd.cond, x, { ...c, inCondition: true });
					return cond ? mergeState(cond, evalList(cmd.body, cond, c)) : null;
				}),
			);
		case "for": {
			redirectSubs(cmd.redirects, st, ctx);
			for (const word of cmd.words ?? []) analyzeSubs(word, st, ctx);
			const values = cmd.words ? expandWords(cmd.words, st) : null;
			return both(fixpoint(st, ctx, (x, c) => evalList(cmd.body, setVar(x, cmd.name, values), c)));
		}
		case "case": {
			redirectSubs(cmd.redirects, st, ctx);
			analyzeSubs(cmd.subject, st, ctx);
			let out: State | null = st;
			for (const item of cmd.items) out = mergeState(out, evalList(item.body, st, ctx));
			return both(out);
		}
		case "function": {
			// The body runs when called, with the caller's state; see callFunction.
			const def = { body: cmd.body, src: ctx.src };
			if (!ctx.dry) ctx.funcDefs.push({ name: cmd.name, def, state: st });
			return { ok: { ...st, funcs: new Map(st.funcs).set(cmd.name, def) }, fail: null };
		}
	}
}

function applyAssignments(st: State, words: Word[], alwaysSucceeds: boolean): Outcome {
	let ok = st;
	let fail = st;
	let mayFail = false;
	for (const word of words) {
		const m = ASSIGN.exec(word.text);
		if (!m) continue;
		const name = m[1];
		const offset = m[0].length;
		if (m[2] || word.text[offset] === "(") {
			ok = setVar(ok, name, null);
			fail = setVar(fail, name, null);
			continue;
		}
		const tail = word.text.slice(offset);
		const base = word.start + offset;
		const hasSubst = word.subs.some((s) => s.kind === "command" || s.kind === "backtick");
		const okValue = expandText(word, tail, base, ok, { assignment: true });
		const failValue = hasSubst ? expandText(word, tail, base, ok, { assignment: true, substFails: true }) : okValue;
		const prev = (s: State): Val => (m[3] ? getVar(s, name) : one(""));
		if (alwaysSucceeds) {
			ok = setVar(ok, name, concat(prev(ok), mergeVal(okValue, failValue)));
			fail = ok;
			continue;
		}
		const nextFail = setVar(fail, name, concat(prev(fail), mergeVal(okValue, failValue)));
		ok = setVar(ok, name, concat(prev(ok), okValue));
		fail = nextFail;
		mayFail ||= hasSubst;
	}
	return { ok, fail: mayFail ? fail : null };
}

interface Invocation {
	/** Command name after wrappers; null when dynamic or unknown. */
	name: string | null;
	args: Word[];
	elevated: boolean;
	xargs: boolean;
	/** Run through a wrapper other than `command`/`builtin`, so shell builtins do not affect our state. */
	wrapped: boolean;
	/** The wrapper changes directory (env -C, sudo -D). */
	chdir: boolean;
}

function unwrap(argv: Word[], st: State): Invocation {
	const inv: Invocation = { name: null, args: [], elevated: false, xargs: false, wrapped: false, chdir: false };
	let k = 0;
	while (k < argv.length) {
		const value = literalOf(argv[k], st);
		if (value === null) return inv;
		const name = value.slice(value.lastIndexOf("/") + 1);
		const withArg = WRAPPERS.get(name);
		if (!withArg) {
			inv.name = name;
			inv.args = argv.slice(k + 1);
			return inv;
		}
		k++;
		if (name !== "command" && name !== "builtin") inv.wrapped = true;
		if (name === "sudo" || name === "doas") inv.elevated = true;
		if (name === "xargs") inv.xargs = true;
		while (k < argv.length) {
			const opt = literalOf(argv[k], st);
			if (opt === null) return inv;
			if (opt === "--") {
				k++;
				break;
			}
			if (name === "env" && ASSIGN.test(opt)) {
				k++;
				continue;
			}
			if (!opt.startsWith("-") || opt === "-") break;
			if (name === "command" && (opt === "-v" || opt === "-V")) {
				inv.name = ":";
				return inv;
			}
			if (name === "env" && (opt === "-S" || opt.startsWith("--split-string"))) return inv;
			if ((name === "env" && (opt === "-C" || opt.startsWith("--chdir"))) || (name === "sudo" && (opt === "-D" || opt.startsWith("--chdir")))) {
				inv.chdir = true;
			}
			k += withArg.includes(opt) ? 2 : 1;
		}
		if (name === "timeout") k++;
	}
	return inv;
}

/** Judge rm/mv/chmod/chown from their resolved operands. Has no effect on state, so loop passes skip it. */
function checkOwned(cmd: SimpleCommand, inv: Invocation, st0: State, ctx: Ctx): void {
	if (ctx.dry) return;
	const st = inv.chdir ? withCwd(st0, null) : st0;
	const name = inv.name as string;
	let recursive = false;
	let force = false;
	let options = true;
	let unknown = inv.xargs;
	let allScratch = true;
	const operands: Word[] = [];
	for (const word of inv.args) {
		const v = literalOf(word, st);
		if (options && v !== null && v.startsWith("-") && v !== "-") {
			if (v === "--") options = false;
			else if (v.startsWith("--")) {
				recursive ||= v === "--recursive";
				force ||= v === "--force";
			} else {
				recursive ||= /[rR]/.test(v);
				force ||= v.includes("f");
			}
			continue;
		}
		operands.push(word);
	}
	const followLast = name === "chmod" || name === "chown";
	const needScratch = name === "rm" && recursive && force;
	for (const word of operands) {
		const paths = resolvePaths(word, st);
		if (paths === null) {
			unknown = true;
			const prefix = literalPrefix(word.text);
			const root = prefix.startsWith("/") ? protectedRoot(prefix, false) : null;
			if (root) report(ctx, "critical", "path", root);
			continue;
		}
		for (const path of paths) {
			const root = protectedRoot(path, followLast);
			if (root) report(ctx, "critical", "path", root);
			if (needScratch && allScratch && !scratchPath(path)) allScratch = false;
		}
	}
	for (const r of cmd.redirects) {
		if (r.heredoc || !r.op.includes(">") || /^(\d+|-)$/.test(r.target.text)) continue;
		for (const path of resolvePaths(r.target, st) ?? []) {
			if (SAFE_DEVICES.test(normalizePath(path))) continue;
			const root = protectedRoot(path, true);
			if (root) report(ctx, "critical", "path", root);
		}
	}
	if (needScratch && (unknown || !allScratch)) report(ctx, "critical", "risk", RM_RF);
	if (name === "rm" && (inv.elevated || ctx.elevated)) report(ctx, "high", "risk", SUDO_RM);
	blank(ctx, cmd.start, cmd.end);
}

interface ShellArgs {
	command: Word | null;
	/** No -c and no script file: the shell reads its script from stdin. */
	stdinScript: boolean;
	errexit: boolean;
}

function shellArgs(args: Word[], st: State): ShellArgs | null {
	let errexit = false;
	for (let k = 0; k < args.length; k++) {
		const a = literalOf(args[k], st);
		if (a === null) return null;
		if (a === "--") return { command: null, stdinScript: k + 1 >= args.length, errexit };
		if (a === "-o" || a === "+o" || a === "-O" || a === "+O") {
			if (a === "-o" && literalOf(args[k + 1], st) === "errexit") errexit = true;
			k++;
			continue;
		}
		if (/^-[a-zA-Z]+$/.test(a)) {
			if (a.includes("e")) errexit = true;
			if (a.includes("c")) return { command: args[k + 1] ?? null, stdinScript: false, errexit };
			continue;
		}
		if (a.startsWith("--") || a.startsWith("+")) continue;
		return { command: null, stdinScript: false, errexit };
	}
	return { command: null, stdinScript: true, errexit };
}

function shellCommand(inv: Invocation, st: State, ctx: Ctx): void {
	if (ctx.dry) return;
	const sh = shellArgs(inv.args, st);
	if (!sh?.command) return;
	const values = expandWord(sh.command, st, { noSplit: true });
	if (!values) return;
	const child = childState(inv.chdir ? withCwd(st, null) : st, sh.errexit);
	let ok = true;
	for (const text of values) {
		if (!analyzeNested(text, child, ctx, childOverrides(ctx, inv), true).ok) ok = false;
	}
	if (ok) blank(ctx, sh.command.start, sh.command.end);
}

function heredocs(cmd: SimpleCommand, inv: Invocation | null, st: State, ctx: Ctx, piped: boolean): void {
	if (ctx.dry) return;
	for (const r of cmd.redirects) {
		const doc = r.heredoc;
		if (!doc || doc.bodyEnd <= doc.bodyStart) continue;
		const body = ctx.src.slice(doc.bodyStart, doc.bodyEnd);
		const name = inv?.name ?? null;
		if (inv && name && SHELLS.has(name)) {
			const sh = shellArgs(inv.args, st);
			const literal = doc.quoted || !/[$`\\]/.test(body);
			if (sh?.stdinScript && literal) {
				const child = childState(inv.chdir ? withCwd(st, null) : st, sh.errexit);
				const nested = analyzeNested(body, child, ctx, childOverrides(ctx, inv), true);
				if (nested.ok) {
					blank(ctx, doc.bodyStart, doc.bodyEnd);
					continue;
				}
			}
			keep(ctx, doc.bodyStart, doc.bodyEnd);
			continue;
		}
		// File contents written by cat/tee are data, unless the shell runs substitutions inside them.
		const data = (name === "cat" || name === "tee") && !piped && !ctx.inSubstitution;
		if (data && (doc.quoted || !/\$\(|`/.test(body))) blank(ctx, doc.bodyStart, doc.bodyEnd);
		else keep(ctx, doc.bodyStart, doc.bodyEnd);
	}
}

function changeDir(args: Word[], st: State): Outcome {
	const unknown = { ok: withCwd(st, null), fail: st };
	const target = args.find((w) => !/^-[LPe@]+$|^--$/.test(literalOf(w, st) ?? ""));
	if (!target) return unknown;
	const values = expandWord(target, st);
	if (!values) return unknown;
	const next = new Set<string>();
	for (const v of values) {
		if (v === "-" || /^[+-]\d+$/.test(v)) return unknown;
		if (v.startsWith("/")) next.add(normalizePath(v));
		else if (!st.cwd) return unknown;
		else for (const c of st.cwd) next.add(v === "" ? c : normalizePath(`${c}/${v}`));
	}
	return { ok: withCwd(st, next.size > CAP ? null : next), fail: st };
}

function setOptions(args: Word[], st: State): State {
	let errexit = st.errexit;
	for (let k = 0; k < args.length; k++) {
		const a = literalOf(args[k], st);
		if (a === null || !/^[-+]./.test(a) || a === "--") break;
		if (a === "-o" || a === "+o") {
			if (literalOf(args[k + 1], st) === "errexit") errexit = a === "-o";
			k++;
		} else if (a.includes("e")) errexit = a.startsWith("-");
	}
	return { ...st, errexit };
}

function declare(name: string, args: Word[], st: State): Outcome {
	let s = st;
	let opaqueValues = false;
	for (const word of args) {
		const m = ASSIGN.exec(word.text);
		if (m) {
			s = opaqueValues ? setVar(s, m[1], null) : (applyAssignments(s, [word], true).ok ?? s);
			continue;
		}
		const v = literalOf(word, s);
		if (v === null) continue;
		if (/^[-+]/.test(v)) opaqueValues ||= /[aAn]/.test(v);
		else if (/^[A-Za-z_]\w*$/.test(v) && name !== "export" && name !== "readonly") s = setVar(s, v, null);
	}
	return both(s);
}

function forget(name: string, args: Word[], st: State): State {
	if (name === "printf") {
		const k = args.findIndex((w) => literalOf(w, st) === "-v");
		const target = k >= 0 ? literalOf(args[k + 1], st) : null;
		return target ? setVar(st, target, null) : st;
	}
	let s = st;
	for (const word of args) {
		const v = literalOf(word, st);
		const m = v && !v.startsWith("-") ? /^([A-Za-z_]\w*)/.exec(v) : null;
		if (m) s = setVar(s, m[1], null);
	}
	return s;
}

function joinWords(words: Word[], st: State): string[] | null {
	let alts = [""];
	for (const [k, word] of words.entries()) {
		const values = expandWord(word, st, { noSplit: true });
		if (!values) return null;
		const next: string[] = [];
		for (const a of alts) for (const v of values) next.push(k ? `${a} ${v}` : v);
		if (next.length > CAP) return null;
		alts = next;
	}
	return alts;
}

function evalEval(args: Word[], st: State, ctx: Ctx, plain: boolean): Outcome {
	const texts = joinWords(args, st);
	if (!texts) return both(plain ? forgetAll(st) : st);
	let out: State | null = null;
	let ok = true;
	for (const text of texts) {
		const nested = analyzeNested(text, st, ctx);
		ok &&= nested.ok;
		out = mergeState(out, nested.ok ? nested.state : forgetAll(st));
	}
	if (ok) for (const word of args) blank(ctx, word.start, word.end);
	return both(plain ? out : st);
}

function trap(args: Word[], st: State, ctx: Ctx): void {
	if (ctx.dry) return;
	const action = args[0];
	const first = literalOf(action, st);
	if (!action || first === "-p" || first === "-l" || first === "-" || first === "") return;
	const values = expandWord(action, st, { noSplit: true });
	if (!values) return;
	let ok = true;
	for (const text of values) {
		if (!KEYWORDS.test(text)) continue;
		if (!analyzeNested(text, st, ctx).ok) ok = false;
		else ctx.traps.push({ text, state: st, event: ctx.events.length, inLoop: ctx.inLoop });
	}
	if (ok) blank(ctx, action.start, action.end);
}

function evalSimple(cmd: SimpleCommand, st: State, ctx: Ctx, piped: boolean): Outcome {
	for (const word of cmd.words) analyzeSubs(word, st, ctx);
	redirectSubs(
		cmd.redirects.filter((r) => !r.heredoc),
		st,
		ctx,
	);
	let k = 0;
	while (k < cmd.words.length && ASSIGN.test(cmd.words[k].text)) k++;
	const inv = k < cmd.words.length ? unwrap(cmd.words.slice(k), st) : null;
	heredocs(cmd, inv, st, ctx, piped);
	if (inv?.name && OWNED.has(inv.name)) {
		checkOwned(cmd, inv, st, ctx);
		return both(st);
	}
	keep(ctx, cmd.start, cmd.end);
	if (!inv) return applyAssignments(st, cmd.words, false);
	const name = inv.name;
	if (name === null) return both(st);
	const plain = !inv.wrapped;
	if (SHELLS.has(name)) shellCommand(inv, st, ctx);
	if (name === "trap") trap(inv.args, st, ctx);
	if (name === "eval") return evalEval(inv.args, st, ctx, plain);
	if (!plain) return both(st);
	switch (name) {
		case "cd":
		case "pushd":
			return changeDir(inv.args, st);
		case "popd":
			return both(withCwd(st, null));
		case "set":
			return { ok: setOptions(inv.args, st), fail: null };
		case "export":
		case "declare":
		case "typeset":
		case "local":
		case "readonly":
			return declare(name, inv.args, st);
		case "unset":
		case "read":
		case "mapfile":
		case "readarray":
		case "getopts":
		case "let":
		case "printf":
			return both(forget(name, inv.args, st));
		case "source":
		case ".":
			return both(forgetAll(st));
		case "return":
			if (ctx.returns) {
				ctx.returns.push(st);
				return { ok: null, fail: null };
			}
			return exitHere(st, ctx);
		case "exit":
			return exitHere(st, ctx);
		default: {
			const def = st.funcs.get(name);
			return def ? callFunction(name, def, st, ctx) : both(st);
		}
	}
}

function exitHere(st: State, ctx: Ctx): Outcome {
	if (ctx.depth === 0 && !ctx.dry) ctx.exits.push(st);
	return { ok: null, fail: null };
}

/** A child shell starts without the caller's functions or function call. */
function childOverrides(ctx: Ctx, inv: Invocation): Partial<Ctx> {
	return { elevated: ctx.elevated || inv.elevated, inSubstitution: false, calls: new Set(), returns: null };
}

/** Run a function body in the current shell, as bash does, so its effects on state carry over. */
function runFunction(def: FunctionDef, st: State, ctx: Ctx): State | null {
	const returns: State[] = [];
	const sameSrc = def.src === ctx.src;
	const inner: Ctx = sameSrc ? { ...ctx, returns } : { ...ctx, returns, src: def.src, spans: [], blanks: [] };
	const out = evalCommand(def.body, st, inner, false);
	if (!sameSrc) finish(inner);
	return returns.reduce<State | null>(mergeState, mergeState(out.ok, out.fail));
}

function callFunction(name: string, def: FunctionDef, st: State, ctx: Ctx): Outcome {
	ctx.called.add(name);
	if (ctx.calls.has(name) || ctx.calls.size >= MAX_DEPTH) return both(forgetAll(st));
	return both(runFunction(def, st, { ...ctx, calls: new Set([...ctx.calls, name]) }));
}

/** State a trap runs with at exit: values set after the trap come from the end of the script. */
function trapExitState(trap: TrapRecord, events: string[], final: State): State | null {
	const changed = new Set(events.slice(trap.event));
	if (!trap.inLoop && !changed.size) return null;
	if (trap.inLoop || changed.has("*all*")) return mergeState(trap.state, final);
	let vars = trap.state.vars;
	for (const name of changed) if (name !== "*cwd*") vars = vars.set(name, getVar(final, name));
	return { ...trap.state, vars, cwd: changed.has("*cwd*") ? final.cwd : trap.state.cwd };
}

// ---------------------------------------------------------------- entry point

/**
 * Text fallback for rm with recursive and force flags before the first path
 * argument. One pass over the tokens of each line, so long opaque text stays
 * linear; a separator or another rm ends the flags of the previous rm.
 */
function textualRmRf(text: string): boolean {
	if (!/\brm\b/i.test(text)) return false;
	for (const line of text.split("\n")) {
		let inRm = false;
		let recursive = false;
		let force = false;
		for (const token of line.split(/\s+/)) {
			if (/(^|\W)rm$/i.test(token)) {
				inRm = true;
				recursive = force = false;
				continue;
			}
			if (!inRm) continue;
			const flags = /^-([a-z]+)/i.exec(token)?.[1];
			if (flags) {
				recursive ||= /r/i.test(flags);
				force ||= /f/i.test(flags);
			} else if (token.startsWith("--")) {
				recursive ||= /^--recursive\b/i.test(token);
				force ||= /^--force\b/i.test(token);
			}
			if (recursive && force) return true;
			if (token.includes("/") || /[;&|]$/.test(token)) inRm = false;
		}
	}
	return false;
}

function textualProtectedPath(text: string): string | null {
	if (!TEXT_PATH_COMMAND.test(text)) return null;
	for (const token of text.split(/\s+/)) {
		if (SAFE_DEVICES.test(token)) continue;
		const root = protectedPaths.find((r) => token === r || token.startsWith(`${r}/`));
		if (root) return root;
	}
	return null;
}

/**
 * Analyze one bash command as the bash tool would run it in `cwd` with `env`.
 * `parsed` is false only when the precise analysis was abandoned (syntax it
 * does not support, too large, too much work) and the text patterns decided.
 */
export function analyzeCommand(command: string, cwd: string = process.cwd(), env: Env = process.env): Analysis {
	if (!KEYWORDS.test(command)) return { findings: [], maxSeverity: "safe", parsed: true };
	let findings: Finding[] = [];
	let units: string[] = [];
	let wholes: string[] = [];
	let parsed = true;
	let error: string | undefined;
	try {
		if (command.length > MAX_LENGTH) throw new BudgetExceeded();
		const list = parseScript(command);
		const ctx: Ctx = {
			src: command,
			findings,
			units,
			wholes,
			spans: [],
			blanks: [],
			events: [],
			traps: [],
			exits: [],
			depth: 0,
			dry: false,
			budget: { left: MAX_EVALS },
			inLoop: false,
			inCondition: false,
			inSubstitution: false,
			elevated: false,
			calls: new Set(),
			called: new Set(),
			funcDefs: [],
			returns: null,
		};
		// BASH_ENV is sourced before the command runs, so it could set anything.
		const start: State = { cwd: one(normalizePath(cwd)), vars: Vars.EMPTY, env: env.BASH_ENV ? null : env, errexit: false, funcs: NO_FUNCS };
		const end = evalList(list, start, ctx);
		const final = ctx.exits.reduce<State | null>(mergeState, end) ?? start;
		for (const trap of ctx.traps.slice(0, MAX_TRAPS)) {
			const exitState = trapExitState(trap, ctx.events, final);
			if (exitState) analyzeNested(trap.text, exitState, ctx);
		}
		// Functions never called directly may still run (by a dynamic name, say): check them once.
		for (const { name, def, state } of ctx.funcDefs) {
			if (!ctx.called.has(name)) runFunction(def, mergeState(state, final) ?? state, { ...ctx, calls: new Set([name]) });
		}
		finish(ctx);
	} catch (caught) {
		parsed = false;
		if (!(caught instanceof ShellSyntaxError || caught instanceof BudgetExceeded)) error = caught instanceof Error ? caught.message : String(caught);
		findings = [];
		units = [command];
		wholes = [command];
	} finally {
		realCache.clear();
		parseCache.clear();
		envCache.clear();
	}
	for (const text of units) {
		const root = textualProtectedPath(text);
		if (root) findings.push({ severity: "critical", kind: "path", detail: root });
		if (textualRmRf(text)) findings.push({ severity: "critical", kind: "risk", detail: RM_RF });
		for (const risk of TEXT_RISKS) {
			if (risk.pattern.test(text)) findings.push({ severity: risk.severity, kind: "risk", detail: risk.detail });
		}
	}
	if (wholes.some((text) => FORK_BOMB.test(text))) findings.push({ severity: "critical", kind: "risk", detail: "Fork bomb" });

	const seen = new Set<string>();
	findings = findings.filter((f) => {
		const key = `${f.severity}|${f.kind}|${f.detail}`;
		if (seen.has(key)) return false;
		seen.add(key);
		return true;
	});
	findings.sort((a, b) => (a.kind === b.kind ? 0 : a.kind === "path" ? -1 : 1));
	const maxSeverity = findings.some((f) => f.severity === "critical") ? "critical" : findings.length ? "high" : "safe";
	return { findings, maxSeverity, parsed, error };
}
