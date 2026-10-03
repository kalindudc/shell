import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { type Command, type SimpleCommand, ShellSyntaxError, parseScript } from "../shell.ts";

function firstCommand(src: string): Command {
	return parseScript(src)[0].andOr.first.commands[0];
}

function simple(src: string): SimpleCommand {
	const cmd = firstCommand(src);
	assert.equal(cmd.type, "simple");
	return cmd as SimpleCommand;
}

describe("parseScript", () => {
	it("splits lists, and-or chains and pipelines", () => {
		const list = parseScript("a && b || c | d; e &\nf");
		assert.equal(list.length, 3);
		assert.deepEqual(
			list[0].andOr.rest.map((r) => r.op),
			["&&", "||"],
		);
		assert.equal(list[0].andOr.rest[1].pipeline.commands.length, 2);
		assert.equal(list[1].background, true);
	});

	it("keeps quotes, escapes and continuations inside words", () => {
		assert.deepEqual(
			simple("rm -rf '/tmp/a b' \"$X\"/c \\\n  d\\ e").words.map((w) => w.text),
			["rm", "-rf", "'/tmp/a b'", '"$X"/c', "d\\ e"],
		);
	});

	it("records heredoc bodies and delimiters", () => {
		const src = "cat > /tmp/f <<'EOF'\nrm -rf / (\nEOF\necho after";
		const list = parseScript(src);
		const doc = (list[0].andOr.first.commands[0] as SimpleCommand).redirects.find((r) => r.heredoc)?.heredoc;
		assert.ok(doc);
		assert.equal(doc.quoted, true);
		assert.equal(src.slice(doc.bodyStart, doc.bodyEnd), "rm -rf / (\n");
		assert.equal(list.length, 2);
	});

	it("finds substitutions, including heredocs inside $(...)", () => {
		const word = simple("git commit -m \"$(cat <<'EOF'\ndon't (stop)\nEOF\n)\"").words[3];
		assert.equal(word.subs.length, 1);
		assert.equal(word.subs[0].kind, "command");
		assert.match(word.subs[0].text, /^cat <<'EOF'\ndon't \(stop\)\nEOF\n$/);
	});

	it("parses compound commands", () => {
		assert.equal(firstCommand("if a; then b; elif c; then d; else e; fi").type, "if");
		assert.equal(firstCommand("while read x; do echo $x; done < f").type, "while");
		assert.equal(firstCommand("for f in a b; do rm $f; done").type, "for");
		assert.equal(firstCommand('case "$x" in /tmp/*) rm -rf "$x";; *) echo no;; esac').type, "case");
		assert.equal(firstCommand("f() { rm -rf \"$1\"; }").type, "function");
		assert.equal(firstCommand("(cd /tmp && ls)").type, "subshell");
		assert.equal(firstCommand("{ echo a; echo b; } > /tmp/out").type, "group");
	});

	it("handles case patterns inside $(...)", () => {
		assert.equal(simple("echo $(case x in a) echo hi;; esac) done").words.length, 3);
	});

	it("rejects unsupported or broken input", () => {
		for (const src of ["echo 'x", "fi", "( echo", "echo $(x", "for ((i=0; i<3; i++)); do :; done"]) {
			assert.throws(() => parseScript(src), ShellSyntaxError, src);
		}
	});
});
