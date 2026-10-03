/**
 * Minimal Herdr socket client: one `pane.report_metadata` request per call.
 * Free of pi imports so it is testable against a fake socket.
 */

import net from "node:net";
import type { HerdrTarget, LabelTokens } from "./labels.ts";

/** Metadata source id; separate from the managed integration's `herdr:pi`. */
export const SOURCE = "user:pi-herdr-label";

const DEFAULT_TIMEOUT_MS = 1000;

// Herdr keeps the highest seq per source and pane and drops older reports.
// Starting from the clock keeps it increasing across pi restarts in one pane.
let seq = Date.now() * 1000;

export interface ReportResult {
	/** Set when Herdr rejected the report or could not be reached. */
	error?: string;
}

export function reportTokens(target: HerdrTarget, tokens: LabelTokens, timeoutMs = DEFAULT_TIMEOUT_MS): Promise<ReportResult> {
	seq += 1;
	const request = {
		id: `${SOURCE}:${seq}`,
		method: "pane.report_metadata",
		params: { pane_id: target.paneId, source: SOURCE, tokens, seq },
	};

	return new Promise((resolve) => {
		let buf = "";
		let settled = false;
		const socket = net.createConnection(target.socketPath);
		const finish = (result: ReportResult) => {
			if (settled) return;
			settled = true;
			clearTimeout(timer);
			socket.destroy();
			resolve(result);
		};
		const timer = setTimeout(() => finish({ error: `herdr did not answer; timed out after ${timeoutMs}ms` }), timeoutMs);
		timer.unref?.();

		socket.on("connect", () => socket.write(`${JSON.stringify(request)}\n`));
		socket.on("error", (err) => finish({ error: err.message }));
		socket.on("end", () => finish({ error: "herdr closed the socket without answering" }));
		socket.on("data", (chunk) => {
			buf += chunk;
			const newline = buf.indexOf("\n");
			if (newline === -1) return;
			try {
				const response = JSON.parse(buf.slice(0, newline));
				finish(response.error ? { error: `${response.error.code}: ${response.error.message}` } : {});
			} catch (err) {
				finish({ error: `unreadable herdr response: ${(err as Error).message}` });
			}
		});
	});
}
