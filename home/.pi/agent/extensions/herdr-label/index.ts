/**
 * herdr-label: show what each pi agent is working on in the Herdr sidebar.
 *
 * Reports two pane metadata tokens beside Herdr's managed pi integration,
 * which owns lifecycle state (working/idle/blocked) and is left untouched:
 *
 *   $goal    the pi session name (set by /name or an auto-naming extension)
 *   $cortex  "#<id>" of the cortex task this session last wrote to
 *            (cortex_update, or bash `cortex update|edit|mv <id>` / `cortex add`)
 *
 * Render them with a pi row layout in ~/.config/herdr/config.toml, e.g.
 *   [ui.sidebar.agents.rows_by_agent]
 *   pi = [["state_icon", "workspace", "tab"], ["$cortex", "$goal"]]
 *
 * Herdr drops tokens on a server restart, so every session start re-reports
 * both tokens (null clears one). The cortex task is saved as a custom session
 * entry so resume, reload and /tree restore it. Only the interactive (TUI)
 * session reports; SDK sessions such as minions share the pane and must not.
 *
 * /herdr-label shows the current labels and the last delivery error.
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { reportTokens } from "./herdr.ts";
import { ENTRY_TYPE, buildTokens, cortexTaskFrom, herdrTarget, restoreState } from "./labels.ts";

function textOf(content: readonly { type: string; text?: string }[]): string {
	return content.map((c) => (c.type === "text" ? (c.text ?? "") : "")).join("\n");
}

export default function (pi: ExtensionAPI) {
	const target = herdrTarget(process.env);
	if (!target) return;

	let active = false;
	let cortex: number | null = null;
	let lastSent: string | undefined;
	let lastError: string | undefined;

	const publish = () => {
		if (!active) return;
		const tokens = buildTokens(pi.getSessionName(), cortex);
		const key = JSON.stringify(tokens);
		if (key === lastSent) return;
		lastSent = key;
		void reportTokens(target, tokens).then((result) => {
			lastError = result.error;
			// Forget what was sent so the next change retries the full set.
			if (result.error && lastSent === key) lastSent = undefined;
		});
	};

	const restore = (ctx: ExtensionContext) => {
		cortex = restoreState(ctx.sessionManager.getBranch()).cortex;
		lastSent = undefined;
		publish();
	};

	pi.on("session_start", (_event, ctx) => {
		if (ctx.mode !== "tui") return;
		active = true;
		restore(ctx);
	});

	pi.on("session_tree", (_event, ctx) => {
		if (active) restore(ctx);
	});

	pi.on("session_info_changed", () => publish());

	pi.on("tool_result", (event) => {
		if (!active || event.isError) return;
		const id = cortexTaskFrom(event.toolName, event.input, textOf(event.content));
		if (id === undefined || id === cortex) return;
		cortex = id;
		pi.appendEntry(ENTRY_TYPE, { cortex });
		publish();
	});

	pi.on("session_shutdown", async (event) => {
		// Other reasons start a new session in this pane, which re-reports.
		if (!active || event.reason !== "quit") return;
		await reportTokens(target, buildTokens(undefined, null));
	});

	pi.registerCommand("herdr-label", {
		description: "Show the labels this session reports to the Herdr sidebar",
		handler: async (_args, ctx) => {
			const { goal, cortex: task } = buildTokens(pi.getSessionName(), cortex);
			const lines = [
				`pane ${target.paneId}`,
				`goal: ${goal ?? "(none; name the session with /name)"}`,
				`cortex: ${task ?? "(none yet)"}`,
			];
			if (lastError) lines.push(`last error: ${lastError}`);
			ctx.ui.notify(lines.join("\n"), lastError ? "warning" : "info");
		},
	});
}
