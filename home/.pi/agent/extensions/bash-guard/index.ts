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
 *
 * Scratch paths (/tmp) are writable: destructive cleanup such as
 * `rm -rf /tmp/build` is allowed when every target lives under a writable
 * path. Escapes like `rm -rf /tmp/../etc` stay blocked.
 */

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

interface RiskPattern {
	pattern: RegExp;
	severity: "critical" | "high";
	description: string;
	/** Skip this risk when every path target in the command is under a writable path. */
	writablePathExempt?: boolean;
}

/** Scratch directories the agent may freely create, modify, and clean up. */
export const writablePaths = ["/tmp"];

/** System paths that stay auto-blocked for rm/mv/chmod/chown. */
const protectedPaths = ["/", "/bin", "/boot", "/dev", "/etc", "/lib", "/proc", "/root", "/sbin", "/sys", "/usr"];

const riskPatterns: RiskPattern[] = [
	// Critical - Auto-blocked, no exceptions (except writable scratch paths)
	{
		pattern: /\brm\s+[^/\n]*(-[a-z]*r[a-z]*f|-[a-z]*f[a-z]*r)/i,
		severity: "critical",
		description: "Recursive force delete (rm -rf)",
		writablePathExempt: true,
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
		pattern: /(^|[;&]\s*|\|\|?\s*|&&\s*)(sudo\s+)?(shutdown|reboot|halt|poweroff)\b/im,
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

/** Resolve . and .. segments textually so "/tmp/../etc" is not mistaken for /tmp. */
export function normalizePath(path: string): string {
	const absolute = path.startsWith("/");
	const resolved: string[] = [];
	for (const segment of path.split("/")) {
		if (segment === "" || segment === ".") continue;
		if (segment === "..") resolved.pop();
		else resolved.push(segment);
	}
	return (absolute ? "/" : "") + resolved.join("/");
}

export function isWritablePath(path: string): boolean {
	const normalized = normalizePath(path);
	return writablePaths.some((root) => normalized === root || normalized.startsWith(root + "/"));
}

/** Split on whitespace while keeping quoted spans (including their spaces) as one token. */
function splitTokens(segment: string): string[] {
	const tokens: string[] = [];
	let current = "";
	let quote: string | null = null;
	for (const char of segment) {
		if (quote) {
			if (char === quote) quote = null;
			current += char;
		} else if (char === '"' || char === "'") {
			quote = char;
			current += char;
		} else if (/\s/.test(char)) {
			if (current) {
				tokens.push(current);
				current = "";
			}
		} else {
			current += char;
		}
	}
	if (current) tokens.push(current);
	return tokens;
}

/**
 * True when every non-flag token after each `rm` in the command is a path
 * under a writable root. Unknown targets (relative paths, globs outside
 * writable roots, command substitutions) keep strict handling.
 */
export function allTargetsWritable(command: string): boolean {
	let sawTarget = false;
	for (const segment of command.split(/[;&|\n]/)) {
		const tokens = splitTokens(segment.trim());
		const rmIndex = tokens.findIndex((token) => token === "rm" || token.endsWith("/rm"));
		if (rmIndex === -1) continue;
		for (const raw of tokens.slice(rmIndex + 1)) {
			let token = raw;
			const quote = token[0];
			if ((quote === '"' || quote === "'") && token.length >= 2 && token.endsWith(quote)) {
				token = token.slice(1, -1);
			}
			if (token === "--" || token.startsWith("-")) continue;
			sawTarget = true;
			if (!isWritablePath(token)) return false;
		}
	}
	return sawTarget;
}

interface CommandAnalysis {
	risks: Array<{ pattern: RiskPattern; match: string }>;
	maxSeverity: "critical" | "high" | "safe";
	protectedPathViolation: string | null;
}

export function analyzeCommand(command: string): CommandAnalysis {
	const risks: Array<{ pattern: RiskPattern; match: string }> = [];
	let maxSeverity: "critical" | "high" | "safe" = "safe";

	for (const riskPattern of riskPatterns) {
		if (riskPattern.writablePathExempt && allTargetsWritable(command)) continue;
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

export default function (pi: ExtensionAPI): void {
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
			{ timeout: 30_000 },
		);

		if (!allow) {
			ctx.ui.notify("Command blocked", "warning");
			return { block: true, reason: "Blocked by user" };
		}

		return undefined;
	});
}
