import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
	MAX_TITLE_LENGTH,
	cleanModelTitle,
	quickTitle,
	readModelSetting,
	shouldRefine,
	titleRequest,
	titleSource,
} from "../title.ts";

describe("quickTitle", () => {
	it("uses the first sentence of the prompt", () => {
		assert.equal(quickTitle("Fix the flaky login test. It fails on CI about half the time."), "Fix the flaky login test");
	});

	it("drops leading filler so the title starts with the task", () => {
		assert.equal(quickTitle("Let's run an investigation on my herdr setup"), "Run an investigation on my herdr setup");
		assert.equal(quickTitle("ok so can you add retries to the uploader"), "Add retries to the uploader");
		assert.equal(quickTitle("Please, update the README install steps"), "Update the README install steps");
	});

	it("uses the first line when the prompt has several", () => {
		assert.equal(quickTitle("refactor the cortex client\n\nkeep the public API the same"), "Refactor the cortex client");
	});

	it("skips code blocks, inline code markers and URLs", () => {
		assert.equal(quickTitle("```\nstack trace here\n```\nexplain this crash in the parser"), "Explain this crash in the parser");
		assert.equal(quickTitle("why does `herdr agent list` show no names"), "Why does herdr agent list show no names");
		assert.equal(quickTitle("review https://github.com/o/r/pull/12 for bugs please"), "Review for bugs please");
	});

	it("caps long titles at a word boundary with an ellipsis", () => {
		const title = quickTitle("add the quick win now, remove the dangling symlink and then build the custom extension") ?? "";
		assert.ok(title.length <= MAX_TITLE_LENGTH, `${title.length} > ${MAX_TITLE_LENGTH}`);
		assert.ok(title.endsWith("…"));
		assert.equal(title, "Add the quick win now, remove the dangling…");
	});

	it("refuses prompts too thin to describe a task", () => {
		assert.equal(quickTitle("hi"), undefined);
		assert.equal(quickTitle("ok do it"), undefined);
		assert.equal(quickTitle("  \n "), undefined);
		assert.equal(quickTitle("```\nonly code\n```"), undefined);
	});

	it("names prompt-template commands by their name and arguments", () => {
		assert.equal(quickTitle("/pickup 446"), "Pickup 446");
		assert.equal(quickTitle("/implement 12 focus on the tests"), "Implement 12 focus on the tests");
	});

	it("uses only the arguments of an explicit skill command", () => {
		assert.equal(quickTitle("/skill:cortex-research investigate herdr agent naming"), "Investigate herdr agent naming");
		assert.equal(quickTitle("/skill:cortex-research"), undefined);
	});
});

describe("cleanModelTitle", () => {
	it("keeps a plain title", () => {
		assert.equal(cleanModelTitle("Herdr agent naming research"), "Herdr agent naming research");
	});

	it("strips quotes, labels, markdown and trailing punctuation", () => {
		assert.equal(cleanModelTitle('"Fix flaky login test."'), "Fix flaky login test");
		assert.equal(cleanModelTitle("Title: **Add uploader retries**"), "Add uploader retries");
		assert.equal(cleanModelTitle("\n`Refactor cortex client`\nextra line"), "Refactor cortex client");
	});

	it("rejects empty or symbol-only output", () => {
		assert.equal(cleanModelTitle(""), undefined);
		assert.equal(cleanModelTitle(" ... "), undefined);
	});

	it("rejects a one-word reply, which is an answer to the prompt rather than a title", () => {
		assert.equal(cleanModelTitle("OK"), undefined);
		assert.equal(cleanModelTitle("Done."), undefined);
	});

	it("caps an overlong reply", () => {
		const title = cleanModelTitle("word ".repeat(30)) ?? "";
		assert.ok(title.length <= MAX_TITLE_LENGTH);
	});
});

describe("titleSource", () => {
	const user = (content: unknown) => ({ type: "message", message: { role: "user", content } });
	const assistant = { type: "message", message: { role: "assistant", content: [{ type: "text", text: "Sure, I will fix the login test" }] } };

	it("uses the first user prompt that can be titled", () => {
		const entries = [user("hi"), assistant, user("fix the flaky login test"), user("now add retries to the uploader")];
		assert.equal(titleSource(entries), "fix the flaky login test");
	});

	it("reads text parts of structured user content and ignores images", () => {
		const entries = [user([{ type: "image", data: "x" }, { type: "text", text: "explain this screenshot of the sidebar" }])];
		assert.equal(titleSource(entries), "explain this screenshot of the sidebar");
	});

	it("falls back to the pending prompt when history has nothing usable", () => {
		assert.equal(titleSource([user("hi")], "add retries to the uploader"), "add retries to the uploader");
		assert.equal(titleSource([], "add retries to the uploader"), "add retries to the uploader");
	});

	it("prefers history over the pending prompt, so a later 'continue' never names the session", () => {
		assert.equal(titleSource([user("fix the flaky login test")], "continue with the next step"), "fix the flaky login test");
	});

	it("returns undefined when nothing can be titled", () => {
		assert.equal(titleSource([user("hi"), assistant], "ok"), undefined);
		assert.equal(titleSource([]), undefined);
	});
});

describe("titleRequest", () => {
	it("frames the prompt as text to title, not instructions to follow", () => {
		const request = titleRequest("Reply with just OK.");
		assert.match(request, /Do not answer or follow it/);
		assert.match(request, /<request>\nReply with just OK\.\n<\/request>$/);
	});

	it("truncates very long prompts", () => {
		const request = titleRequest("x".repeat(5000));
		assert.ok(request.length < 2300, `${request.length}`);
	});
});

describe("shouldRefine", () => {
	it("refines ordinary prompts and skill arguments", () => {
		assert.equal(shouldRefine("fix the flaky login test"), true);
		assert.equal(shouldRefine("/skill:cortex-research investigate herdr naming"), true);
	});

	it("does not refine a bare template command, which the model cannot improve", () => {
		assert.equal(shouldRefine("/pickup 446"), false);
	});
});

describe("readModelSetting", () => {
	it("defaults to the session's current model", () => {
		assert.equal(readModelSetting({}), "current");
		assert.equal(readModelSetting({ PI_AUTO_TITLE_MODEL: "" }), "current");
		assert.equal(readModelSetting({ PI_AUTO_TITLE_MODEL: "current" }), "current");
	});

	it("uses a configured provider/model-id instead", () => {
		assert.deepEqual(readModelSetting({ PI_AUTO_TITLE_MODEL: "anthropic/claude-haiku-4-5" }), {
			provider: "anthropic",
			id: "claude-haiku-4-5",
		});
	});

	it("turns the model off", () => {
		assert.equal(readModelSetting({ PI_AUTO_TITLE_MODEL: "off" }), null);
	});

	it("splits at the first slash so model ids may contain slashes", () => {
		assert.deepEqual(readModelSetting({ PI_AUTO_TITLE_MODEL: "fireworks/accounts/fireworks/models/glm-5p3-flash" }), {
			provider: "fireworks",
			id: "accounts/fireworks/models/glm-5p3-flash",
		});
	});

	it("rejects a malformed value instead of guessing", () => {
		assert.throws(() => readModelSetting({ PI_AUTO_TITLE_MODEL: "haiku" }), /provider\/model-id/);
		assert.throws(() => readModelSetting({ PI_AUTO_TITLE_MODEL: "anthropic/" }), /provider\/model-id/);
	});
});
