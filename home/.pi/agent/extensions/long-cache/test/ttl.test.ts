import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { isLongLived, withOneHourTtl } from "../ttl.ts";

describe("isLongLived", () => {
	it("accepts the user's own top-level threads", () => {
		assert.equal(isLongLived({ parentThreadId: null, lifecycleOwnerThreadId: null, originPluginId: null, title: "Fix the chip" }), true);
	});

	it("accepts Loom planners and refuses other Loom threads", () => {
		assert.equal(isLongLived({ originPluginId: "loom", title: "Loom plan: Force-Env lanes" }), true);
		assert.equal(isLongLived({ originPluginId: "loom", title: "LANE-25 · Übertool lanes" }), false);
	});

	it("refuses child threads, workflow workers and plugin-run threads", () => {
		assert.equal(isLongLived({ parentThreadId: "thr_parent" }), false);
		assert.equal(isLongLived({ lifecycleOwnerThreadId: "thr_owner" }), false);
		assert.equal(isLongLived({ originPluginId: "shuttle", title: "Review Shopify/edgey#1583" }), false);
		assert.equal(isLongLived({ originPluginId: "automations", title: "Journal" }), false);
	});
});

describe("withOneHourTtl", () => {
	const payload = {
		model: "claude-opus-5-5",
		system: [{ type: "text", text: "sys", cache_control: { type: "ephemeral" } }],
		tools: [{ name: "read" }, { name: "bash", cache_control: { type: "ephemeral" } }],
		messages: [
			{ role: "user", content: [{ type: "text", text: "hi" }] },
			{ role: "user", content: [{ type: "text", text: "next", cache_control: { type: "ephemeral" } }] },
		],
	};

	it("sets ttl 1h on every ephemeral breakpoint and leaves the rest alone", () => {
		const next = withOneHourTtl(payload) as typeof payload;
		assert.deepEqual(next.system[0].cache_control, { type: "ephemeral", ttl: "1h" });
		assert.deepEqual(next.tools[1].cache_control, { type: "ephemeral", ttl: "1h" });
		assert.deepEqual(next.messages[1].content[0].cache_control, { type: "ephemeral", ttl: "1h" });
		assert.equal("cache_control" in next.tools[0], false);
		assert.equal(next.messages[0].content[0].text, "hi");
	});

	it("does not mutate the original payload", () => {
		withOneHourTtl(payload);
		assert.deepEqual(payload.system[0].cache_control, { type: "ephemeral" });
	});

	it("returns undefined when nothing changes", () => {
		assert.equal(withOneHourTtl({ messages: [{ role: "user", content: "hi" }] }), undefined);
		assert.equal(withOneHourTtl({ system: [{ cache_control: { type: "ephemeral", ttl: "1h" } }] }), undefined);
	});
});
