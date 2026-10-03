import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { ENTRY_TYPE, completions, parseToggle, restoreEnabled, statusIcon } from "../state.ts";

const saved = (enabled: unknown, customType = ENTRY_TYPE) => ({ type: "custom", customType, data: { enabled } });

describe("restoreEnabled", () => {
	it("defaults to on", () => {
		assert.equal(restoreEnabled([]), true);
		assert.equal(restoreEnabled([{ type: "message" }, saved(false, "other")]), true);
	});

	it("uses the latest saved state on the branch", () => {
		assert.equal(restoreEnabled([saved(false)]), false);
		assert.equal(restoreEnabled([saved(false), saved(true)]), true);
		assert.equal(restoreEnabled([saved(true), saved(false), saved("bogus")]), false);
	});
});

describe("parseToggle", () => {
	it("toggles without an argument", () => {
		assert.deepEqual(parseToggle("", true), { kind: "set", enabled: false });
		assert.deepEqual(parseToggle("  ", false), { kind: "set", enabled: true });
	});

	it("accepts explicit states and status", () => {
		assert.deepEqual(parseToggle("on", false), { kind: "set", enabled: true });
		assert.deepEqual(parseToggle("OFF", true), { kind: "set", enabled: false });
		assert.deepEqual(parseToggle("status", true), { kind: "status" });
		assert.deepEqual(parseToggle("maybe", true), { kind: "usage" });
	});
});

describe("statusIcon", () => {
	it("shows a locked padlock when on and an open one when off", () => {
		assert.equal(statusIcon(true), "🔒");
		assert.equal(statusIcon(false), "🔓");
	});
});

describe("completions", () => {
	it("filters by prefix", () => {
		assert.deepEqual(
			completions("o").map((c) => c.value),
			["on", "off"],
		);
		assert.equal(completions("x"), null);
	});
});
