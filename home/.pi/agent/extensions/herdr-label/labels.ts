/**
 * Pure label logic for herdr-label, kept free of pi imports so it is
 * unit-testable under plain `node --test`.
 */

/** Custom session entry that remembers the cortex task across resume and reload. */
export const ENTRY_TYPE = "herdr-label";

export interface LabelState {
	/** The cortex task this session last wrote to, or null. */
	cortex: number | null;
}

/** Herdr sidebar tokens; null clears a token so stale labels never linger. */
export interface LabelTokens {
	goal: string | null;
	cortex: string | null;
}

export interface HerdrTarget {
	socketPath: string;
	paneId: string;
}

/**
 * Only writes count. Reads (`cortex show`, `cortex_recall`) are often a look at
 * an example task, and following them would mislabel the stream.
 */
const CORTEX_WRITE = /\bcortex\s+(?:update|edit|mv)\s+(\d+)\b/g;
const CORTEX_ADD = /\bcortex\s+add\b/;
const ADDED_ID = [/^\[(\d+)\]/m, /"id":\s*(\d+)/];

function positiveInt(value: unknown): number | undefined {
	const n = typeof value === "number" ? value : Number.NaN;
	return Number.isInteger(n) && n > 0 ? n : undefined;
}

/** The cortex task a successful tool call shows this session working on, if any. */
export function cortexTaskFrom(toolName: string, input: Record<string, unknown>, output: string): number | undefined {
	if (toolName === "cortex_update") return positiveInt(input.task_id);
	if (toolName !== "bash" || typeof input.command !== "string") return undefined;

	const command = input.command;
	let id: number | undefined;
	for (const match of command.matchAll(CORTEX_WRITE)) id = Number(match[1]);
	if (CORTEX_ADD.test(command)) {
		for (const pattern of ADDED_ID) {
			const added = pattern.exec(output);
			if (added) return Number(added[1]);
		}
	}
	return id;
}

export function buildTokens(sessionName: string | undefined, cortex: number | null): LabelTokens {
	const goal = sessionName?.trim();
	return { goal: goal ? goal : null, cortex: cortex === null ? null : `#${cortex}` };
}

/** The latest saved state on the current session branch. */
export function restoreState(entries: readonly unknown[]): LabelState {
	let cortex: number | null = null;
	for (const entry of entries as any[]) {
		if (entry?.type !== "custom" || entry.customType !== ENTRY_TYPE) continue;
		const saved = entry.data?.cortex;
		if (saved === null) cortex = null;
		else if (positiveInt(saved) !== undefined) cortex = saved;
	}
	return { cortex };
}

/** The Herdr socket and pane to report to, or undefined outside a Herdr pane. */
export function herdrTarget(env: Record<string, string | undefined>): HerdrTarget | undefined {
	const { HERDR_ENV, HERDR_SOCKET_PATH, HERDR_PANE_ID } = env;
	if (HERDR_ENV !== "1" || !HERDR_SOCKET_PATH || !HERDR_PANE_ID) return undefined;
	return { socketPath: HERDR_SOCKET_PATH, paneId: HERDR_PANE_ID };
}
