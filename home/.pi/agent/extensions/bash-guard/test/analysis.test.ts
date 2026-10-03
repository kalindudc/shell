import { after, before, describe, it } from "node:test";
import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, symlinkSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { analyzeCommand, isScratchPath } from "../analyze.ts";

/** A non-scratch session directory; it does not need to exist. */
const REPO = "/work/repo";
/** Environment pi passes to bash, fixed so results do not depend on the machine. */
const ENV = { HOME: "/Users/agent", PATH: "/usr/bin:/bin" };

/** Severity from the full analysis; fails if the command fell back to text matching. */
function severity(command: string, cwd = REPO, env: Record<string, string> = ENV): string {
	const analysis = analyzeCommand(command, cwd, env);
	assert.equal(analysis.error, undefined, `analyzer error for: ${command}`);
	assert.equal(analysis.parsed, true, `did not parse: ${command}`);
	return analysis.maxSeverity;
}

function assertAll(expected: string, commands: string[], cwd = REPO): void {
	for (const command of commands) assert.equal(severity(command, cwd), expected, command);
}

describe("isScratchPath", () => {
	it("treats /tmp, /private/tmp and their children as scratch", () => {
		for (const p of ["/tmp", "/tmp/build", "/tmp/build/cache", "/private/tmp/x", "/tmp/a/../b"]) {
			assert.equal(isScratchPath(p), true, p);
		}
	});

	it("rejects lookalikes and escapes", () => {
		for (const p of ["/tmpfoo", "/etc", "/tmp/../etc", "/private", "/var/tmp/x"]) {
			assert.equal(isScratchPath(p), false, p);
		}
	});
});

describe("/tmp work is ignored", () => {
	it("allows direct deletes under /tmp", () => {
		assertAll("safe", [
			"rm -rf /tmp/build",
			"rm -rf /tmp",
			"rm -rf /tmp/*",
			"rm -rf '/tmp/my dir'",
			"rm -rf /tmp/* /tmp/build2 && echo done",
			"rm -rf /private/tmp/x",
			'rm -rf "/tmp/cortex-$$"',
			"rm -rf /tmp/a > /tmp/log 2>&1",
			"chmod -R 755 /tmp/x && chown -R me /tmp/x && mv /tmp/x /tmp/y",
		]);
	});

	it("follows cd into /tmp", () => {
		assertAll("safe", [
			"cd /tmp && rm -rf split-probe && mkdir split-probe && cd split-probe",
			"cd /tmp && rm -rf pi-web-access && git clone --depth 1 https://github.com/x/y.git 2>&1 | tail -3",
			"mkdir -p /tmp/starship_test && cd /tmp/starship_test && rm -rf .git ./* 2>/dev/null; git init -q -b main",
			"cd /tmp/work || exit 1\nrm -rf build",
			"set -e\ncd /tmp/work\nrm -rf build",
			"cd /tmp/a && (cd b && rm -rf c) && rm -rf d",
			"cd /tmp && rm -r oc4 && git clone --depth 1 https://github.com/sst/opencode.git oc4",
		]);
	});

	it("allows relative deletes when the session itself runs in /tmp", () => {
		assert.equal(severity("rm -rf build node_modules", "/tmp/proj"), "safe");
		assert.equal(severity("rm -rf build node_modules", "/private/tmp/proj"), "safe");
	});

	it("tracks variables and mktemp results that point into /tmp", () => {
		assertAll("safe", [
			"set -e; R=/work/repo; P=/tmp/cortex-proto; rm -rf $P; mkdir -p $P/node_modules; cp -R $R/src $P/src",
			"set -e; R=/tmp/critics-run; rm -rf \\\n  \"$R\" && mkdir -p \"$R\"",
			'SB=$(mktemp -d /tmp/cx-agents-XXXX); export CORTEX_DB=$SB/cortex.db XDG_CONFIG_HOME=$SB\n./bin/cortex init > /dev/null 2>&1\nrm -rf "$SB"',
			'T=$(mktemp -d -p /tmp) && cd "$T" && rm -rf build',
			"tmp=$(mktemp -d /tmp/cortex-atomic-check.XXXXXX) && trap 'rm -rf \"$tmp\"' EXIT && cd \"$tmp\" && git init -q",
			'D=/tmp/x; for f in "$D"/*.log; do rm -rf "$f"; done',
		]);
	});

	it("checks traps with the values they will see at exit", () => {
		assertAll("safe", [
			"cd /work/repo && tmp=$(mktemp -d /tmp/x.XXXXXX) && trap 'rm -rf \"$tmp\"' EXIT && TMP_X=\"$tmp\" node -e 'x'",
			"T=/tmp/a; trap \"rm -rf $T\" EXIT; T=/work/repo",
		]);
		assert.equal(severity("T=/tmp/a; trap 'rm -rf \"$T\"' EXIT; T=/work/repo"), "critical");
		assert.equal(severity("T=/tmp/a; trap 'rm -rf \"$T\"' EXIT; T=/tmp/b; exit 0"), "safe");
	});

	it("resolves variables the command never assigns from the environment", () => {
		assertAll("safe", [
			"cd /work/repo && T=$(mktemp -d /tmp/thm.XXXX) && echo hi > $T/a; echo next; rm -rf $T",
			'rm -rf "${SCRATCH:-/tmp}/x"',
		]);
		assert.equal(severity('rm -rf "$HOME/x"'), "critical");
		assert.equal(severity('rm -rf "${SCRATCH:-/tmp}/x"', REPO, { SCRATCH: "/work" }), "critical");
		assert.equal(severity("rm -rf $T", REPO, { BASH_ENV: "/x/env.sh" }), "critical");
	});

	it("matches fallback patterns one command at a time", () => {
		assertAll("safe", [
			'export CORTEX_DB=/tmp/c.db; rm -f "$CORTEX_DB"\nhome/bin/cortex rm "$ID" -f\necho -n "GET / -> "',
			"comm -23 /tmp/a.txt /tmp/b.txt | sort > /tmp/rm.txt && ls /",
			"docker run --rm -v /usr/share:/data alpine ls",
		]);
	});

	it("follows shell functions into their bodies", () => {
		assertAll("safe", [
			'set -e\nTMP=$(mktemp -d /tmp/smoke-XXXX)\nrun() { pnpm exec bun index.ts "$@"; }\nrun init >/dev/null\nrm -rf "$TMP"',
			'TMP=$(mktemp -d /tmp/x.XXXX); cleanup() { rm -rf "$TMP"; }; trap cleanup EXIT; echo hi',
			'go() { cd /tmp/w || return 1; rm -rf build; }; go',
			"f() { f; }; f; echo done",
		]);
		assertAll("critical", [
			'f() { T=/work/repo; }; T=/tmp/a; f; rm -rf "$T"',
			'f() { cd /tmp/w; return; }; f; rm -rf build',
			'f() { rm -rf "$1"; }; f /tmp/a',
			"f() { rm -rf ~; }",
			"f() { f; }; f; rm -rf \"$X\"",
		]);
	});

	it("handles line continuations", () => {
		assertAll("safe", ["rm -rf /tmp/cortex-432-gate \\\n  /tmp/cortex-432-db && mkdir -p /tmp/cortex-432-gate"]);
	});

	it("ignores file contents written by cat or tee heredocs", () => {
		assertAll("safe", [
			"cat > /tmp/critic-task.md <<'EOF'\nReview: rm -rf / is blocked, and mv /usr is too.\nEOF",
			"cd /tmp && mkdir -p test-install && cd test-install && cat > package.json << 'EOF'\n{\"scripts\": {\"clean\": \"rm -rf dist\"}}\nEOF\nnpm install",
			"cd /tmp && rm -rf split-probe && mkdir split-probe && cd split-probe && cat > entry.ts <<'EOF'\nimport x from \"/\";\n// mv a b\nEOF\nbun build entry.ts",
			"tee /tmp/notes.txt <<EOF\nrm -rf / chmod /etc\nEOF",
		]);
	});

	it("analyzes nested shells against /tmp", () => {
		assertAll("safe", [
			"bash -c 'cd /tmp/x && rm -rf y'",
			"timeout 10 bash -lc \"rm -rf /tmp/x\"",
			"bash -e <<'EOF'\ncd /tmp/foo\nrm -rf bar\nEOF",
			"eval 'rm -rf /tmp/x'",
		]);
	});

	it("does not mistake later flags for rm flags", () => {
		assertAll("safe", [
			"cd $(cat /tmp/cortex-466-proto-dir) && test -L node_modules && rm node_modules && pnpm install --frozen-lockfile",
			"cd /tmp/cortex_clean && touch bin/cortex && head -c 1000 /dev/zero | tr '\\0' x > out/bundle.js && rm -f bin/cortex",
		]);
	});

	it("skips commands without any guarded keyword", () => {
		for (const command of ["git add -A && git status", "echo 'unterminated", "terraform fmt -recursive"]) {
			const analysis = analyzeCommand(command, REPO, ENV);
			assert.deepEqual([analysis.maxSeverity, analysis.findings.length, analysis.parsed], ["safe", 0, true], command);
		}
	});

	it("keeps ordinary commands allowed", () => {
		assertAll("safe", [
			"echo hi > /tmp/foo",
			"mkdir -p /tmp/build && cd /tmp/build",
			"ls -la /",
			"rm -r build",
			"git status --short",
		]);
	});
});

describe("everything outside /tmp stays guarded", () => {
	it("blocks rm -rf outside /tmp", () => {
		assertAll("critical", [
			"rm -rf node_modules",
			"rm -r -f build",
			"rm --recursive --force build",
			"rm -rf ~",
			"rm -rf /tmpfoo",
			"rm -rf /",
			"rm -rf --no-preserve-root /",
			"rm -rf /tmp /etc/foo",
			"find /tmp -name x | xargs rm -rf",
		]);
	});

	it("blocks protected system paths", () => {
		assertAll("critical", ["rm /etc/passwd", "mv /usr/bin/env /tmp/env", "chmod -R 777 /", "cd / && rm -r etc"]);
	});

	it("blocks escapes from /tmp", () => {
		assertAll("critical", [
			"rm -rf /tmp/../etc",
			"cd /tmp && rm -rf ..",
			"rm -rf /tmp/{a,../../etc}",
			"rm -rf /tmp/x/$(echo ../../etc)",
			'P="/tmp/a /work/repo"; rm -rf $P',
		]);
	});

	it("does not trust a cd that may have failed", () => {
		assertAll("critical", [
			"cd /tmp/x; rm -rf build",
			"cd /tmp/x\nrm -rf build",
			"(cd /tmp && rm -rf a); rm -rf b",
			"cd /tmp | rm -rf a",
			"if cd /tmp/x; then :; fi; rm -rf build",
			"bash <<'EOF'\ncd /tmp/foo\nrm -rf bar\nEOF",
		]);
	});

	it("does not trust unknown or reassigned variables", () => {
		assertAll("critical", [
			'rm -rf "$UNSET/"',
			"P=/tmp/x; P=/etc; rm -rf $P",
			"for d in /tmp/a /work/repo; do rm -rf \"$d\"; done",
			"x=/tmp/a; while true; do rm -rf $x; x=/work/repo; done",
			'T=$(cat /tmp/dir.path); rm -rf "$T"',
			'T=$(mktemp -d); rm -rf "$T"',
			'SB=$(mktemp -d /tmp/x.XXXX); rm -rf "$SB/"*',
		]);
	});

	it("keeps opaque or nested code strict", () => {
		assertAll("critical", [
			"rm -rf /tmp/a && bash -c \"rm -rf ~\"",
			"ssh host 'rm -rf /tmp/a'",
			'eval "rm -rf /"',
			"cat <<EOF | bash\nrm -rf ~\nEOF",
			"cat > /tmp/f <<EOF\n$(rm -rf ~)\nEOF",
			"f() { rm -rf ~; }",
			"echo $(rm -rf ~)",
		]);
	});

	it("falls back to text matching when the command cannot be parsed", () => {
		for (const [command, expected] of [
			["rm -rf / 'unterminated", "critical"],
			["rm -f 'unterminated", "safe"],
			// Not valid bash (`}` is an argument here), but still caught by the text patterns.
			[":(){ :|: };:", "critical"],
		]) {
			const analysis = analyzeCommand(command, REPO);
			assert.equal(analysis.parsed, false, command);
			assert.equal(analysis.error, undefined, command);
			assert.equal(analysis.maxSeverity, expected, command);
		}
	});

	it("keeps the other critical rules", () => {
		assertAll("critical", ["dd if=/dev/zero of=/dev/sda", ":(){ :|:& };:", "mkfs.ext4 /dev/sda1", "sudo reboot", "echo x && shutdown -h now"]);
	});

	it("still prompts (high) for elevated or service commands", () => {
		assertAll("high", [
			"sudo rm -rf /tmp/a",
			"sudo rm /work/repo/file",
			"sudo tee /etc/hosts <<EOF\n127.0.0.1 x\nEOF",
			"systemctl stop nginx",
		]);
	});
});

describe("symlinks out of /tmp", () => {
	let dir = "";
	const outside = path.dirname(fileURLToPath(import.meta.url));

	before(() => {
		dir = mkdtempSync("/tmp/bash-guard-test-");
		symlinkSync(outside, path.join(dir, "repo-link"));
		symlinkSync("/usr", path.join(dir, "usr-link"));
		mkdirSync(path.join(dir, "real"));
	});

	after(() => rmSync(dir, { recursive: true, force: true }));

	it("allows removing the link itself", () => {
		assert.equal(severity(`rm -rf ${dir}/repo-link ${dir}/real`), "safe");
	});

	it("blocks deletes that pass through the link", () => {
		assertAll("critical", [
			`rm -rf ${dir}/repo-link/`,
			`rm -rf ${dir}/repo-link/*`,
			`cd ${dir}/repo-link && rm -rf build`,
			`cd ${dir}/real && rm -rf ../repo-link/x`,
			`rm ${dir}/usr-link/bin/x`,
		]);
	});
});
