/**
 * Bash Guard Extension
 *
 * Minimal protection against dangerous bash commands executed by LLMs through pi.
 *
 * Two levels:
 * - Critical: Auto-blocked without exception (rm -rf, fork bombs, disk ops, system paths)
 * - High: Prompts user for confirmation (sudo rm, service changes, /etc writes)
 *
 * Everything else is allowed.
 */

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

interface RiskPattern {
	pattern: RegExp;
	severity: "critical" | "high";
	description: string;
}

export default function (pi: ExtensionAPI): void {
	const riskPatterns: RiskPattern[] = [
		// Critical - Auto-blocked, no exceptions
		{
			pattern: /\brm\s+[^/\n]*(-[a-z]*r[a-z]*f|-[a-z]*f[a-z]*r)/i,
			severity: "critical",
			description: "Recursive force delete (rm -rf)",
		},
		{
			pattern: /:\(\)\{.*:\|:.*\};:/,
			severity: "critical",
			description: "Fork bomb",
		},
		{
			pattern: /\b(mkfs\.|dd\s+.*of=\/dev\/)/i,
			severity: "critical",
			description: "Disk formatting or raw device write",
		},
		{
			pattern: /\b(shutdown|reboot|halt|poweroff)\b/i,
			severity: "critical",
			description: "System shutdown/reboot",
		},

		// High - Prompt user for confirmation
		{
			pattern: /\bsudo\s+rm\b/i,
			severity: "high",
			description: "Elevated delete operation",
		},
		{
			pattern: /\bsudo\s+.*(>|tee)\s*\/etc\//i,
			severity: "high",
			description: "Writing to /etc with sudo",
		},
		{
			pattern: /\b(systemctl\s+(stop|disable|mask)|service\s+\S+\s+(stop|disable|mask))/i,
			severity: "high",
			description: "Stopping or disabling system service",
		},
	];

	const protectedPaths = ["/", "/bin", "/boot", "/dev", "/etc", "/lib", "/proc", "/root", "/sbin", "/sys", "/usr"];

	interface CommandAnalysis {
		risks: Array<{ pattern: RiskPattern; match: string }>;
		maxSeverity: "critical" | "high" | "safe";
		protectedPathViolation: string | null;
	}

	function analyzeCommand(command: string): CommandAnalysis {
		const risks: Array<{ pattern: RiskPattern; match: string }> = [];
		let maxSeverity: "critical" | "high" | "safe" = "safe";

		for (const riskPattern of riskPatterns) {
			const match = command.match(riskPattern.pattern);
			if (match) {
				risks.push({ pattern: riskPattern, match: match[0] });
				if (riskPattern.severity === "critical") {
					maxSeverity = "critical";
				} else if (riskPattern.severity === "high" && maxSeverity !== "critical") {
					maxSeverity = "high";
				}
			}
		}

		let protectedPathViolation: string | null = null;
		if (/\b(rm|mv|chmod|chown)\b/.test(command)) {
			// Extract all arguments after the command
			const args = command.split(/\s+/).slice(1);
			for (const arg of args) {
				for (const path of protectedPaths) {
					// Check if argument starts with the protected path
					// This catches /etc, /etc/file, etc but not /home/etc
					if (arg === path || arg.startsWith(path + "/")) {
						protectedPathViolation = path;
						maxSeverity = "critical";
						break;
					}
				}
				if (protectedPathViolation) break;
			}
		}

		return { risks, maxSeverity, protectedPathViolation };
	}

	function formatRiskReport(command: string, analysis: CommandAnalysis): string {
		const lines: string[] = [];
		lines.push("Command:");
		lines.push(`  ${command.split("\n")[0]}`);
		if (command.split("\n").length > 1) lines.push(`  ... (${command.split("\n").length} lines)`);
		lines.push("");

		if (analysis.protectedPathViolation) {
			lines.push(`Protected path: ${analysis.protectedPathViolation}`);
		}
		for (const risk of analysis.risks) {
			lines.push(`Risk: ${risk.pattern.description}`);
		}

		return lines.join("\n");
	}

	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "bash") return undefined;

		const command = event.input.command as string;
		const analysis = analyzeCommand(command);

		if (analysis.maxSeverity === "safe") return undefined;

		const report = formatRiskReport(command, analysis);

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

		const allow = await ctx.ui.confirm(
			"High risk command",
			`${report}\n\nAllow execution?`,
		);

		if (!allow) {
			ctx.ui.notify("Command blocked", "warning");
			return { block: true, reason: "Blocked by user" };
		}

		return undefined;
	});
}
