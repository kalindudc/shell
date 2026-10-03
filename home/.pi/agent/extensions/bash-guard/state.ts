/**
 * Per-session on/off state for the `/bash-guard` command. Pure, so it can be
 * tested without pi. The state is saved as a custom session entry, so it
 * survives reloads and resumes and follows the branch in `/tree`.
 */

export const ENTRY_TYPE = "bash-guard";

/** Whether the guard is on for this session branch: on unless the latest saved entry says off. */
export function restoreEnabled(entries: readonly unknown[]): boolean {
	let enabled = true;
	for (const entry of entries as Array<{ type?: string; customType?: string; data?: { enabled?: unknown } } | undefined>) {
		if (entry?.type !== "custom" || entry.customType !== ENTRY_TYPE) continue;
		if (typeof entry.data?.enabled === "boolean") enabled = entry.data.enabled;
	}
	return enabled;
}

/** Footer status: a locked padlock while the guard checks commands, an open one while it is off. */
export function statusIcon(enabled: boolean): string {
	return enabled ? "🔒" : "🔓";
}

export type ToggleAction = { kind: "set"; enabled: boolean } | { kind: "status" } | { kind: "usage" };

/** What `/bash-guard <args>` asks for. Without an argument it toggles. */
export function parseToggle(args: string, enabled: boolean): ToggleAction {
	switch (args.trim().toLowerCase()) {
		case "":
		case "toggle":
			return { kind: "set", enabled: !enabled };
		case "on":
			return { kind: "set", enabled: true };
		case "off":
			return { kind: "set", enabled: false };
		case "status":
			return { kind: "status" };
		default:
			return { kind: "usage" };
	}
}

const ARGUMENTS = [
	{ value: "on", label: "on", description: "Check bash commands (default)" },
	{ value: "off", label: "off", description: "Run bash commands unchecked in this session" },
	{ value: "status", label: "status", description: "Show whether the guard is on" },
];

export function completions(prefix: string): typeof ARGUMENTS | null {
	const matches = ARGUMENTS.filter((a) => a.value.startsWith(prefix.trim().toLowerCase()));
	return matches.length ? matches : null;
}
