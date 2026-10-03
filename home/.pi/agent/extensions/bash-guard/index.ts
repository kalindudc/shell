/**
 * Bash Guard Extension
 *
 * Minimal protection against dangerous bash commands executed by LLMs through pi.
 *
 * Two levels:
 * - Critical: auto-blocked (rm -rf outside scratch paths, rm/mv/chmod/chown on
 *   system paths, fork bombs, disk formatting, shutdown/reboot)
 * - High: prompts for confirmation (sudo rm, sudo writes to /etc, stopping services)
 *
 * Scratch paths (/tmp and /private/tmp) are ignored completely. The command is
 * parsed and evaluated against the session's working directory so that work
 * like `cd /tmp/x && rm -rf build` or `T=$(mktemp -d /tmp/x.XXXX); rm -rf "$T"`
 * is allowed, while escapes such as `rm -rf /tmp/../etc` or a symlink out of
 * /tmp stay blocked. See analyze.ts for the rules.
 *
 * `/bash-guard` toggles the guard for the current session (`on`, `off`,
 * `status`), and the footer shows 🔒 while it is on and 🔓 while it is off.
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { type Analysis, analyzeCommand } from "./analyze.ts";
import { ENTRY_TYPE, completions, parseToggle, restoreEnabled, statusIcon } from "./state.ts";

const STATUS_KEY = "bash-guard";

function formatReport(command: string, analysis: Analysis): string {
	const lines = command.split("\n");
	const report = ["Command:", `  ${lines[0]}`];
	if (lines.length > 1) report.push(`  ... (${lines.length} lines)`);
	report.push("");
	for (const finding of analysis.findings) {
		report.push(finding.kind === "path" ? `Protected path: ${finding.detail}` : `Risk: ${finding.detail}`);
	}
	return report.join("\n");
}

export default function (pi: ExtensionAPI): void {
	let enabled = true;

	const showStatus = (ctx: ExtensionContext): void => {
		if (!ctx.hasUI) return;
		ctx.ui.setStatus(STATUS_KEY, statusIcon(enabled));
	};

	const restore = (ctx: ExtensionContext): void => {
		enabled = restoreEnabled(ctx.sessionManager.getBranch());
		showStatus(ctx);
	};

	pi.on("session_start", (_event, ctx) => restore(ctx));
	pi.on("session_tree", (_event, ctx) => restore(ctx));

	pi.registerCommand("bash-guard", {
		description: "Toggle the bash guard for this session (on, off, status)",
		getArgumentCompletions: completions,
		handler: async (args, ctx) => {
			const action = parseToggle(args, enabled);
			if (action.kind === "usage") {
				ctx.ui.notify("Usage: /bash-guard [on|off|status]", "warning");
				return;
			}
			if (action.kind === "set" && action.enabled !== enabled) {
				enabled = action.enabled;
				pi.appendEntry(ENTRY_TYPE, { enabled });
				showStatus(ctx);
			}
			if (enabled) ctx.ui.notify("bash-guard is on", "info");
			else ctx.ui.notify("bash-guard is off: bash commands run unchecked in this session", "warning");
		},
	});

	pi.on("tool_call", async (event, ctx) => {
		if (!enabled || event.toolName !== "bash") return undefined;

		const command = event.input.command as string;
		const analysis = analyzeCommand(command, ctx.cwd);

		if (analysis.error && ctx.hasUI) {
			ctx.ui.notify(`bash-guard fell back to pattern matching: ${analysis.error}`, "warning");
		}

		if (analysis.maxSeverity === "safe") return undefined;

		const report = formatReport(command, analysis);

		// Critical: Auto-block
		if (analysis.maxSeverity === "critical") {
			if (ctx.hasUI) {
				ctx.ui.notify("Critical command blocked", "error");
			}
			return {
				block: true,
				reason: `[CRITICAL] Command blocked automatically\n\n${report}`,
			};
		}

		// High: Prompt user
		if (!ctx.hasUI) {
			return {
				block: true,
				reason: `[HIGH] Command blocked in non-interactive mode\n\n${report}`,
			};
		}

		const allow = await ctx.ui.confirm("High risk command", `${report}\n\nAllow execution?`, { timeout: 30_000 });

		if (!allow) {
			ctx.ui.notify("Command blocked", "warning");
			return { block: true, reason: "Blocked by user" };
		}

		return undefined;
	});
}
