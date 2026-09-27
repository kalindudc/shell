import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { analyzeCommand, isWritablePath } from "../index.ts";

describe("isWritablePath", () => {
	it("treats /tmp and its children as writable", () => {
		assert.equal(isWritablePath("/tmp"), true);
		assert.equal(isWritablePath("/tmp/build"), true);
		assert.equal(isWritablePath("/tmp/build/cache"), true);
	});

	it("does not treat lookalikes or escapes as /tmp", () => {
		assert.equal(isWritablePath("/tmpfoo"), false);
		assert.equal(isWritablePath("/etc"), false);
		assert.equal(isWritablePath("/tmp/../etc"), false);
	});
});

describe("analyzeCommand /tmp exemption", () => {
	it("allows rm -rf cleanup under /tmp", () => {
		for (const cmd of [
			"rm -rf /tmp/build",
			"rm -rf /tmp",
			"rm -rf /tmp/*",
			"rm -rf '/tmp/my dir'",
			"rm -rf /tmp/* /tmp/build2 && echo done",
		]) {
			assert.equal(analyzeCommand(cmd).maxSeverity, "safe", cmd);
		}
	});

	it("keeps system paths and escapes blocked", () => {
		for (const cmd of [
			"rm -rf /tmp/../etc",
			"rm -rf /etc",
			"rm -rf /tmp /etc/foo",
			"rm -rf /",
			"rm -rf ~",
			"rm -rf /tmpfoo",
			"rm /etc/passwd",
			"dd if=/dev/zero of=/dev/sda",
			":(){ :|: };:",
		]) {
			assert.equal(analyzeCommand(cmd).maxSeverity, "critical", cmd);
		}
	});

	it("still prompts (high) for sudo rm under /tmp", () => {
		assert.equal(analyzeCommand("sudo rm -rf /tmp/a").maxSeverity, "high");
	});

	it("keeps plain /tmp writes allowed", () => {
		for (const cmd of ["echo hi > /tmp/foo", "mkdir -p /tmp/build && cd /tmp/build"]) {
			assert.equal(analyzeCommand(cmd).maxSeverity, "safe", cmd);
		}
	});
});
