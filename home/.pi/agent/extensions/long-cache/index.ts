/**
 * long-cache: a one-hour Anthropic prompt cache for long-lived threads only.
 *
 * Anthropic's default cache lives five minutes, so a thread that waits longer for the user, a minion
 * or a wake-up writes its whole context to the cache again on the next call. A one-hour cache
 * avoids that, but every cache write then costs 2x the input price instead of 1.25x. Measured over
 * the week to 2026-11-09, that trade saved money only on the user's own top-level threads and
 * Loom planners, so PI_CACHE_RETENTION=long, which applies to every session, is not used.
 *
 * In a bb thread the extension asks bb for the thread's parent and origin once per session and
 * adds ttl "1h" to each cache breakpoint of Anthropic requests when the thread is long-lived.
 * Outside bb it applies only to interactive sessions.
 *
 * Config (env, read at load): PI_LONG_CACHE=off disables it.
 */

import { execFile } from "node:child_process";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { isLongLived, withOneHourTtl } from "./ttl.ts";

function bbThread(threadId: string): Promise<Record<string, unknown> | null> {
	return new Promise((resolve) => {
		execFile("bb", ["thread", "show", threadId, "--json"], { timeout: 15_000 }, (err, stdout) => {
			if (err) return resolve(null);
			try {
				resolve((JSON.parse(stdout) as { thread?: Record<string, unknown> }).thread ?? null);
			} catch {
				resolve(null);
			}
		});
	});
}

export default function (pi: ExtensionAPI) {
	if (process.env.PI_LONG_CACHE === "off") return;
	let eligible: Promise<boolean> = Promise.resolve(false);

	pi.on("session_start", (_event, ctx) => {
		const threadId = process.env.BB_THREAD_ID;
		// A failed lookup keeps the default five-minute cache, which is never wrong, only dearer.
		eligible = threadId ? bbThread(threadId).then((thread) => (thread ? isLongLived(thread) : false)) : Promise.resolve(ctx.hasUI);
	});

	pi.on("before_provider_request", async (event, ctx) => {
		if (ctx.model?.api !== "anthropic-messages") return undefined;
		if (!(await eligible)) return undefined;
		return withOneHourTtl(event.payload);
	});
}
