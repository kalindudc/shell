/**
 * herdr-label: show what each pi agent is working on in the Herdr sidebar.
 *
 * Reports three pane metadata tokens beside Herdr's managed pi integration,
 * which owns lifecycle state (working/idle/blocked) and is left untouched:
 *
 *   $goal      the pi session name (set by /name or an auto-naming extension)
 *   $cortex    "#<id>" of the cortex task this session last wrote to
 *              (cortex_update, or bash `cortex update|edit|mv <id>` / `cortex add`)
 *   $progress  "N/M tasks" when that task is a plan: distinct `task N:` updates
 *              against its Low-Level Tasks, recounted after every cortex write
 *
 * Render them with a pi row layout in ~/.config/herdr/config.toml, e.g.
 *   [ui.sidebar.agents.rows_by_agent]
 *   pi = [["state_icon", "workspace", "tab"], ["$goal"], ["$cortex", "$progress"]]
 *
 * Herdr drops tokens on a server restart, so every session start re-reports
 * every token (null clears one). The cortex task is saved as a custom session
 * entry so resume, reload and /tree restore it. Only the interactive (TUI)
 * session reports; SDK sessions such as minions share the pane and must not.
 *
 * /herdr-label shows the current labels and the last delivery error.
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { reportTokens } from "./herdr.ts";
import { ENTRY_TYPE, buildTokens, cortexTaskFrom, herdrTarget, planProgress, restoreState } from "./labels.ts";

const PROGRESS_TIMEOUT_MS = 3000;

function textOf(content: readonly { type: string; text?: string }[]): string {
	return content.map((c) => (c.type === "text" ? (c.text ?? "") : "")).join("\n");
}

export default function (pi: ExtensionAPI) {
	const target = herdrTarget(process.env);
	if (!target) return;

	let active = false;
	let cortex: number | null = null;
	let progress: string | null = null;
	let lastSent: string | undefined;
	let lastError: string | undefined;

	const publish = () => {
		if (!active) return;
		const tokens = buildTokens(pi.getSessionName(), cortex, progress);
		const key = JSON.stringify(tokens);
		if (key === lastSent) return;
		lastSent = key;
		void reportTokens(target, tokens).then((result) => {
			lastError = result.error;
			// Forget what was sent so the next change retries the full set.
			if (result.error && lastSent === key) lastSent = undefined;
		});
	};

	// Progress is derived from cortex on every refresh, never stored. pi.exec
	// never rejects: a timeout resolves as code 0 with killed set, so treat any
	// failure as "no progress" and let a stale count disappear.
	// Only the latest refresh may publish, so a slow older read never
	// overwrites a newer count or another task's.
	let refreshes = 0;
	const refreshProgress = async () => {
		const run = ++refreshes;
		const id = cortex;
		let next: string | null = null;
		if (id !== null) {
			const result = await pi.exec("cortex", ["show", String(id), "--json"], { timeout: PROGRESS_TIMEOUT_MS });
			if (run !== refreshes) return;
			if (result.code === 0 && !result.killed) {
				try {
					next = planProgress(JSON.parse(result.stdout));
				} catch {
					next = null;
				}
			}
		}
		progress = next;
		publish();
	};

	const restore = (ctx: ExtensionContext) => {
		cortex = restoreState(ctx.sessionManager.getBranch()).cortex;
		progress = null;
		lastSent = undefined;
		publish();
		void refreshProgress();
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
		if (id === undefined) return;
		// Every write can record a task, so recount even when the task is unchanged.
		if (id !== cortex) {
			cortex = id;
			progress = null;
			pi.appendEntry(ENTRY_TYPE, { cortex });
		}
		publish();
		void refreshProgress();
	});

	pi.on("session_shutdown", async (event) => {
		// Other reasons start a new session in this pane, which re-reports.
		if (!active || event.reason !== "quit") return;
		await reportTokens(target, buildTokens(undefined, null));
	});

	pi.registerCommand("herdr-label", {
		description: "Show the labels this session reports to the Herdr sidebar",
		handler: async (_args, ctx) => {
			const { goal, cortex: task } = buildTokens(pi.getSessionName(), cortex, progress);
			const lines = [
				`pane ${target.paneId}`,
				`goal: ${goal ?? "(none; name the session with /name)"}`,
				`cortex: ${task ?? "(none yet)"}`,
				`progress: ${progress ?? "(none)"}`,
			];
			if (lastError) lines.push(`last error: ${lastError}`);
			ctx.ui.notify(lines.join("\n"), lastError ? "warning" : "info");
		},
	});
}
