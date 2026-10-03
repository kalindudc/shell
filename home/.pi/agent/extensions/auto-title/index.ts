/**
 * auto-title: name each pi session after the task in its first prompt.
 *
 * 1. Instant: when the first substantive prompt is submitted, the session is
 *    named from it (first sentence, filler dropped, at most 50 characters).
 *    No network, so it never delays the prompt.
 * 2. Better: a model then rewrites that into a 3-6 word title in the
 *    background, through pi's own model registry (no packages), with thinking
 *    off so it stays quick. By default that is the session's current model.
 *    The result is dropped if the name changed meanwhile, e.g. by /name.
 *
 * Named sessions are never touched. An unnamed session that already has
 * history (resume, /reload) is titled from its first prompt when it starts.
 * Only the interactive (TUI) session titles itself; SDK sessions such as
 * minions do not.
 *
 * The name feeds pi's /resume list, the terminal title, and the herdr-label
 * extension's $goal token in the Herdr sidebar.
 *
 * Config (env, read at load; run /reload after changing):
 *   PI_AUTO_TITLE_MODEL  unset or "current": the session's current model (default)
 *                        "provider/model-id": a fixed model, e.g. anthropic/claude-haiku-4-5
 *                        "off": instant titles only, no model call
 *
 * /auto-title re-titles the current session now and reports any model error.
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { cleanModelTitle, quickTitle, readModelSetting, shouldRefine, titleRequest, titleSource } from "./title.ts";

const SYSTEM_PROMPT =
	"You name coding-agent sessions. Reply with only a title of 3 to 6 words that names the task in the user's request. No quotes and no trailing punctuation.";
const MODEL_TIMEOUT_MS = 15_000;

export default function (pi: ExtensionAPI) {
	const setting = readModelSetting(process.env);

	const modelLabel = (ctx: ExtensionContext): string => {
		if (setting === null) return "off";
		if (setting !== "current") return `${setting.provider}/${setting.id}`;
		return ctx.model ? `current (${ctx.model.provider}/${ctx.model.id})` : "current (none selected)";
	};

	let active = false;
	let titled = false;
	// Bumped per session so a late model reply never renames a different session.
	let generation = 0;
	let lastError: string | undefined;

	/** Ask the model for a better title; applies it only if nothing renamed the session meanwhile. */
	const refine = async (ctx: ExtensionContext, source: string, provisional: string): Promise<void> => {
		if (!setting || !shouldRefine(source)) return;
		const model = setting === "current" ? ctx.model : ctx.modelRegistry.find(setting.provider, setting.id);
		if (!model) {
			lastError = `model ${modelLabel(ctx)} not found`;
			return;
		}
		if (!ctx.modelRegistry.hasConfiguredAuth(model)) {
			lastError = `no authentication configured for ${modelLabel(ctx)}`;
			return;
		}
		const started = generation;
		try {
			// streamSimple with no `reasoning` turns thinking off on every provider,
			// so a reasoning model answers at once instead of spending the budget thinking.
			const reply = await ctx.modelRegistry
				.streamSimple(
					model,
					{
						systemPrompt: SYSTEM_PROMPT,
						messages: [{ role: "user", content: [{ type: "text", text: titleRequest(source) }], timestamp: Date.now() }],
					},
					{ maxTokens: 60, cacheRetention: "none", signal: AbortSignal.timeout(MODEL_TIMEOUT_MS) },
				)
				.result();
			if (reply.stopReason === "error" || reply.stopReason === "aborted") {
				lastError = reply.errorMessage ?? `model call ${reply.stopReason}`;
				return;
			}
			const text = reply.content.map((c) => (c.type === "text" ? c.text : "")).join("");
			const title = cleanModelTitle(text);
			if (!title) {
				lastError = `model returned no usable title: ${JSON.stringify(text.slice(0, 80))}`;
				return;
			}
			lastError = undefined;
			if (generation === started && pi.getSessionName() === provisional) pi.setSessionName(title);
		} catch (err) {
			lastError = (err as Error).message;
		}
	};

	/** Name the session from its source prompt; returns false when there is nothing to title yet. */
	const title = (ctx: ExtensionContext, pending?: string): boolean => {
		const source = titleSource(ctx.sessionManager.getBranch(), pending);
		const provisional = source === undefined ? undefined : quickTitle(source);
		if (source === undefined || provisional === undefined) return false;
		titled = true;
		pi.setSessionName(provisional);
		void refine(ctx, source, provisional);
		return true;
	};

	pi.on("session_start", (_event, ctx) => {
		generation += 1;
		active = ctx.mode === "tui";
		titled = Boolean(pi.getSessionName());
		if (active && !titled) title(ctx);
	});

	pi.on("input", (event, ctx) => {
		if (!active || titled || event.source === "extension") return;
		title(ctx, event.text);
	});

	pi.registerCommand("auto-title", {
		description: "Re-title this session from its first prompt",
		handler: async (_args, ctx) => {
			const source = titleSource(ctx.sessionManager.getBranch());
			const provisional = source === undefined ? undefined : quickTitle(source);
			if (source === undefined || provisional === undefined) {
				ctx.ui.notify("auto-title: no prompt to title yet", "warning");
				return;
			}
			titled = true;
			pi.setSessionName(provisional);
			await refine(ctx, source, provisional);
			const lines = [`Session title: ${pi.getSessionName()}`, `model: ${modelLabel(ctx)}`];
			if (lastError) lines.push(`model error: ${lastError}`);
			ctx.ui.notify(lines.join("\n"), lastError ? "warning" : "info");
		},
	});
}
