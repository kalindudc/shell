/**
 * Pure helpers, kept free of pi imports so they are unit-testable under plain `node --test`.
 */

export interface ThreadFacts {
	parentThreadId?: string | null;
	lifecycleOwnerThreadId?: string | null;
	originPluginId?: string | null;
	title?: string | null;
}

/**
 * Threads that wait on the user, minions or wake-ups for more than five minutes and then resume:
 * the user's own top-level threads and Loom planners. Child threads, PR reviews, Loom workers and
 * automations are short, so the one-hour write price costs them more than the misses it saves.
 */
export function isLongLived(thread: ThreadFacts): boolean {
	if (thread.parentThreadId || thread.lifecycleOwnerThreadId) return false;
	if (!thread.originPluginId) return true;
	return thread.originPluginId === "loom" && (thread.title ?? "").startsWith("Loom plan");
}

/** Adds `ttl: "1h"` to every ephemeral cache breakpoint; returns undefined when there is none to change. */
export function withOneHourTtl(payload: unknown): unknown {
	let changed = false;
	const visit = (value: unknown): unknown => {
		if (Array.isArray(value)) return value.map(visit);
		if (value === null || typeof value !== "object") return value;
		const out: Record<string, unknown> = {};
		for (const [key, child] of Object.entries(value)) {
			if (key === "cache_control" && isShortBreakpoint(child)) {
				out[key] = { ...child, ttl: "1h" };
				changed = true;
			} else {
				out[key] = visit(child);
			}
		}
		return out;
	};
	const next = visit(payload);
	return changed ? next : undefined;
}

function isShortBreakpoint(value: unknown): value is Record<string, unknown> {
	if (value === null || typeof value !== "object") return false;
	const control = value as Record<string, unknown>;
	return control.type === "ephemeral" && control.ttl === undefined;
}
