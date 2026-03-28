/**
 * Bash Guard Extension
 *
 * Minimal protection against dangerous bash commands executed by LLMs through pi.
 *
 * Two levels:
 * - Critical: Auto-blocked without exception (rm -rf, fork bombs, disk ops, system paths)
 * - High: Prompts user for confirmation (sudo rm, service changes, /etc writes)
 *
 * Everything else is allowed with optional logging.
 */

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { isToolCallEventType } from "@mariozechner/pi-coding-agent";

interface RiskPattern {
	pattern: RegExp;
	severity: "critical" | "high";
	description: string;
}

export default function (pi: ExtensionAPI): void {
	// Minimal risk patterns - only absolute necessities
	const riskPatterns: RiskPattern[] = [
		// Critical - Auto-blocked, no exceptions
		{
			pattern: /\brm\s+(-[rf]*r[rf]*|--recursive)\s+(-[rf]*f[rf]*|--force)|rm\s+(-[rf]*f[rf]*|--force)\s+(-[rf]*r[rf]*|--recursive)/i,
			severity: "critical",
			description: "Recursive force delete",
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
			pattern: /\bsudo\s+.*>\s*\/etc\//i,
			severity: "high",
			description: "Writing to /etc with sudo",
		},
		{
			pattern: /\b(systemctl|service)\s+(stop|disable|mask)/i,
			severity: "high",
			description: "Stopping or disabling system service",
		},
	];

	// Protected paths - operations on these are critical
	const protectedPaths = ["/", "/bin", "/boot", "/dev", "/etc", "/lib", "/proc", "/root", "/sbin", "/sys", "/usr"];

	interface CommandAnalysis {
		risks: Array<{ pattern: RiskPattern; match: string }>;
		maxSeverity: "critical" | "high" | "safe";
		protectedPathViolation: string | null;
	}

	// Analyze command for risks
	function analyzeCommand(command: string): CommandAnalysis {
		const risks: Array<{ pattern: RiskPattern; match: string }> = [];
		let maxSeverity: "critical" | "high" | "safe" = "safe";

		// Check for risk patterns
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

		// Check for protected path violations (critical)
		let protectedPathViolation: string | null = null;
		for (const path of protectedPaths) {
			const pathPattern = new RegExp(
				`\\b(rm|mv|chmod|chown)\\s+[^\\n]*${path.replace(/\//g, "\\/")}(?:\\/|\\s|$)`,
				"i",
			);
			if (pathPattern.test(command)) {
				protectedPathViolation = path;
				maxSeverity = "critical";
				break;
			}
		}

		return { risks, maxSeverity, protectedPathViolation };
	}

	// Format risk report
	function formatRiskReport(command: string, analysis: CommandAnalysis): string {
		const lines: string[] = [];
		
		// Show command
		lines.push("Command:");
		lines.push(`  ${command.split("\n")[0]}`);
		if (command.split("\n").length > 1) lines.push(`  ... (${command.split("\n").length} lines)`);
		lines.push("");

		// Show risks
		if (analysis.protectedPathViolation) {
			lines.push(`Protected path: ${analysis.protectedPathViolation}`);
		}
		for (const risk of analysis.risks) {
			lines.push(`Risk: ${risk.pattern.description}`);
		}

		return lines.join("\n");
	}

	// Main guard logic
	pi.on("tool_call", async (event, ctx): Promise<{ block: boolean; reason: string } | undefined> => {
		if (!isToolCallEventType("bash", event)) return undefined;

		const command = event.input.command;
		const analysis = analyzeCommand(command);

		// Safe commands pass through
		if (analysis.maxSeverity === "safe") return undefined;

		const report = formatRiskReport(command, analysis);

		// Critical: Auto-block, no exceptions
		if (analysis.maxSeverity === "critical") {
			if (ctx.hasUI) {
				ctx.ui.notify("Critical command blocked", "error");
			}
			return {
				block: true,
				reason: `[CRITICAL] Command blocked automatically\n\n${report}`,
			};
		}

		// High: Prompt user (or block in non-interactive)
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
