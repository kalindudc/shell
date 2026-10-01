import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { PressCounter, readConfig } from "../press-counter.ts";

describe("PressCounter", () => {
	it("counts down remaining presses and triggers on the last one", () => {
		const counter = new PressCounter(3, 1000);
		assert.equal(counter.press(0), 2);
		assert.equal(counter.press(100), 1);
		assert.equal(counter.press(200), 0);
	});

	it("starts a fresh sequence after triggering", () => {
		const counter = new PressCounter(2, 1000);
		assert.equal(counter.press(0), 1);
		assert.equal(counter.press(100), 0);
		assert.equal(counter.press(200), 1);
	});

	it("restarts the sequence when the gap between presses exceeds the window", () => {
		const counter = new PressCounter(2, 1000);
		assert.equal(counter.press(0), 1);
		assert.equal(counter.press(1001), 1);
		assert.equal(counter.press(1500), 0);
	});

	it("still counts a press exactly at the window boundary", () => {
		const counter = new PressCounter(2, 1000);
		assert.equal(counter.press(0), 1);
		assert.equal(counter.press(1000), 0);
	});

	it("reset() discards an in-progress sequence", () => {
		const counter = new PressCounter(2, 1000);
		assert.equal(counter.press(0), 1);
		counter.reset();
		assert.equal(counter.press(100), 1);
	});

	it("triggers immediately when only one press is required", () => {
		const counter = new PressCounter(1, 1000);
		assert.equal(counter.press(0), 0);
	});

	it("rejects invalid configuration", () => {
		assert.throws(() => new PressCounter(0, 1000), /presses/);
		assert.throws(() => new PressCounter(1.5, 1000), /presses/);
		assert.throws(() => new PressCounter(2, 0), /windowMs/);
	});
});

describe("readConfig", () => {
	it("uses defaults when env vars are unset", () => {
		assert.deepEqual(readConfig({}), { presses: 2, windowMs: 1000 });
	});

	it("reads overrides from env vars", () => {
		assert.deepEqual(
			readConfig({ PI_ESC_ABORT_PRESSES: "3", PI_ESC_ABORT_WINDOW_MS: "750" }),
			{ presses: 3, windowMs: 750 },
		);
	});

	it("throws on malformed values instead of silently defaulting", () => {
		assert.throws(() => readConfig({ PI_ESC_ABORT_PRESSES: "three" }), /PI_ESC_ABORT_PRESSES/);
		assert.throws(() => readConfig({ PI_ESC_ABORT_PRESSES: "0" }), /PI_ESC_ABORT_PRESSES/);
		assert.throws(() => readConfig({ PI_ESC_ABORT_WINDOW_MS: "-5" }), /PI_ESC_ABORT_WINDOW_MS/);
	});
});
