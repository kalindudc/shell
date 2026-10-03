import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { ENTRY_TYPE, buildTokens, cortexTaskFrom, herdrTarget, restoreState } from "../labels.ts";

describe("cortexTaskFrom", () => {
	it("takes the task id from a cortex_update tool call", () => {
		assert.equal(cortexTaskFrom("cortex_update", { task_id: 446, message: "x" }, ""), 446);
	});

	it("ignores a cortex_update call without a positive integer id", () => {
		assert.equal(cortexTaskFrom("cortex_update", { task_id: 0 }, ""), undefined);
		assert.equal(cortexTaskFrom("cortex_update", { task_id: "abc" }, ""), undefined);
		assert.equal(cortexTaskFrom("cortex_update", {}, ""), undefined);
	});

	it("takes the id from bash commands that write to a task", () => {
		assert.equal(cortexTaskFrom("bash", { command: "cortex update 12 -m done --as pi-x" }, ""), 12);
		assert.equal(cortexTaskFrom("bash", { command: "cortex edit 34 --body-file /tmp/b.md" }, ""), 34);
		assert.equal(cortexTaskFrom("bash", { command: "cortex mv 56 --lane shell" }, ""), 56);
	});

	it("uses the last write when a command touches several tasks", () => {
		assert.equal(cortexTaskFrom("bash", { command: "cortex update 1 -m a && cortex update 2 -m b" }, ""), 2);
	});

	it("does not count reads, so looking at an example task keeps the current stream", () => {
		assert.equal(cortexTaskFrom("bash", { command: "cortex show 464 --json | jq .task.body" }, ""), undefined);
		assert.equal(cortexTaskFrom("bash", { command: "cortex memory show 464" }, ""), undefined);
		assert.equal(cortexTaskFrom("cortex_recall", { query: "@464" }, ""), undefined);
	});

	it("takes the new id from cortex add output, plain or JSON", () => {
		assert.equal(cortexTaskFrom("bash", { command: 'cortex add "T" --lane shell' }, "[468] T\n"), 468);
		assert.equal(cortexTaskFrom("bash", { command: 'cortex add "T" --json' }, '{\n  "id": 469,\n  "title": "T"\n}'), 469);
	});

	it("ignores cortex add when the output carries no id", () => {
		assert.equal(cortexTaskFrom("bash", { command: 'cortex add "T"' }, "error: lane not found"), undefined);
	});

	it("ignores unrelated tools and commands", () => {
		assert.equal(cortexTaskFrom("bash", { command: "echo update 12" }, ""), undefined);
		assert.equal(cortexTaskFrom("read", { path: "cortex update 12" }, ""), undefined);
		assert.equal(cortexTaskFrom("bash", {}, ""), undefined);
	});
});

describe("buildTokens", () => {
	it("maps a session name and task to the goal and cortex tokens", () => {
		assert.deepEqual(buildTokens("Fix esc guard", 446), { goal: "Fix esc guard", cortex: "#446" });
	});

	it("clears tokens that have no value, so a new session never shows the old one's labels", () => {
		assert.deepEqual(buildTokens(undefined, null), { goal: null, cortex: null });
		assert.deepEqual(buildTokens("   ", null), { goal: null, cortex: null });
	});

	it("trims the session name", () => {
		assert.deepEqual(buildTokens("  Fix it  ", null), { goal: "Fix it", cortex: null });
	});
});

describe("restoreState", () => {
	const custom = (data: unknown, customType = ENTRY_TYPE) => ({ type: "custom", customType, data });

	it("returns no task for a session without saved state", () => {
		assert.deepEqual(restoreState([]), { cortex: null });
		assert.deepEqual(restoreState([{ type: "message" }, custom({ cortex: 9 }, "other-extension")]), { cortex: null });
	});

	it("restores the latest saved task on the branch", () => {
		assert.deepEqual(restoreState([custom({ cortex: 1 }), { type: "message" }, custom({ cortex: 2 })]), { cortex: 2 });
	});

	it("ignores malformed saved entries", () => {
		assert.deepEqual(restoreState([custom({ cortex: 5 }), custom({ cortex: "x" }), custom(undefined)]), { cortex: 5 });
	});
});

describe("herdrTarget", () => {
	it("returns the socket and pane inside a Herdr pane", () => {
		assert.deepEqual(herdrTarget({ HERDR_ENV: "1", HERDR_SOCKET_PATH: "/s.sock", HERDR_PANE_ID: "w1:p1" }), {
			socketPath: "/s.sock",
			paneId: "w1:p1",
		});
	});

	it("returns undefined outside Herdr or with missing variables", () => {
		assert.equal(herdrTarget({}), undefined);
		assert.equal(herdrTarget({ HERDR_ENV: "0", HERDR_SOCKET_PATH: "/s.sock", HERDR_PANE_ID: "w1:p1" }), undefined);
		assert.equal(herdrTarget({ HERDR_ENV: "1", HERDR_PANE_ID: "w1:p1" }), undefined);
		assert.equal(herdrTarget({ HERDR_ENV: "1", HERDR_SOCKET_PATH: "/s.sock" }), undefined);
	});
});
