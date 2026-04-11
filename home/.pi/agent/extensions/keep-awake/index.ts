/**
 * Keep Awake Extension
 *
 * Prevents the system from sleeping while the pi agent is actively working.
 * Supports macOS (caffeinate) and Linux (systemd-inhibit), with optional
 * keepawake binary as the preferred cross-platform backend.
 *
 * Sleep inhibition starts on agent_start and ends on agent_end or
 * session_shutdown. Reference-counted so parallel sessions (subagents,
 * overlapping agent_start events, etc.) do not prematurely tear down the
 * inhibitor while another session is still running.
 */

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { spawn, type ChildProcess } from "node:child_process";
import { platform } from "node:os";

type Backend = "keepawake" | "caffeinate" | "systemd-inhibit" | null;

function probeKeepawake(): Promise<boolean> {
	return new Promise((resolve) => {
		const probe = spawn("keepawake", ["--version"], { stdio: "ignore" });
		probe.on("error", () => resolve(false));
		probe.on("exit", (code) => resolve(code === 0));
	});
}

async function resolveBackend(): Promise<Backend> {
	if (await probeKeepawake()) {
		return "keepawake";
	}

	const p = platform();
	if (p === "darwin") return "caffeinate";
	if (p === "linux") return "systemd-inhibit";
	return null;
}

function spawnInhibitor(backend: Backend): ChildProcess | null {
	if (backend === "keepawake") {
		return spawn("keepawake", ["-i", "-d"], { stdio: "ignore", detached: true });
	}

	if (backend === "caffeinate") {
		return spawn("caffeinate", ["-i", "-d"], { stdio: "ignore", detached: true });
	}

	if (backend === "systemd-inhibit") {
		// Embed the parent Node PID so we can distinguish inhibitors from
		// different pi OS processes when debugging or cleaning up.
		const who = `pi (pid: ${process.pid})`;
		return spawn(
			"systemd-inhibit",
			[
				"--what=idle:sleep",
				"--who=" + who,
				"--why=Active pi agent session",
				"--mode=block",
				"cat",
			],
			{ stdio: ["pipe", "ignore", "ignore"], detached: true },
		);
	}

	return null;
}

function terminateInhibitor(proc: ChildProcess): void {
	// Closing stdin causes `cat` to exit cleanly, which causes
	// systemd-inhibit to release the lock and terminate. If Node.js
	// crashes, the kernel closes the pipe anyway, so this is inherently
	// crash-safe.
	proc.stdin?.end();

	proc.kill("SIGTERM");

	// Because we spawn with detached:true, the inhibitor gets its own
	// process group. Kill the whole group to guarantee cleanup.
	if (proc.pid && proc.pid > 0) {
		try {
			process.kill(-proc.pid, "SIGTERM");
		} catch {
			// already gone
		}
	}

	// Last-resort force-kill after a short grace period.
	setTimeout(() => {
		if (!proc.pid) return;
		try {
			process.kill(proc.pid, "SIGKILL");
			if (proc.pid > 0) {
				process.kill(-proc.pid, "SIGKILL");
			}
		} catch {
			// already gone
		}
	}, 500);
}

export default function (pi: ExtensionAPI): void {
	const backendPromise = resolveBackend();
	let backend: Backend = null;
	backendPromise.then((b) => {
		backend = b;
	});

	// Reference-count active agent sessions. Only spawn when the count
	// transitions 0 -> 1; only terminate when it transitions 1 -> 0.
	let activeSessions = 0;
	let inhibitorProc: ChildProcess | null = null;
	let notifiedMissing = false;

	const startInhibitor = async (
		ctx?: Parameters<Parameters<typeof pi.on>[1]>[1],
	) => {
		activeSessions++;

		// Already holding an inhibitor; just bump the ref count.
		if (inhibitorProc) return;

		const b = await backendPromise;
		if (!b) {
			activeSessions = Math.max(0, activeSessions - 1);
			if (!notifiedMissing) {
				console.warn(
					"[keep-awake] No supported backend found. Install keepawake or use macOS/Linux with built-in tools.",
				);
				notifiedMissing = true;
			}
			return;
		}

		// If every session ended while we were awaiting the backend, bail out.
		if (activeSessions === 0) return;

		inhibitorProc = spawnInhibitor(b);
		if (!inhibitorProc) {
			activeSessions = Math.max(0, activeSessions - 1);
			return;
		}

		if (ctx?.ui) {
			const theme = ctx.ui.theme;
			ctx.ui.setStatus(
				"keep-awake",
				theme.fg("warning", "☕") + theme.fg("dim", " awake"),
			);
		}

		inhibitorProc.on("error", (err) => {
			console.error(`[keep-awake] ${b} failed:`, err.message);
			inhibitorProc = null;
			if (ctx?.ui) {
				ctx.ui.setStatus("keep-awake", undefined);
			}
		});

		inhibitorProc.on("exit", (code, signal) => {
			// SIGTERM is expected during normal cleanup; null signal + code 0
			// is expected when we close the pipe for systemd-inhibit + cat.
			const expected =
				signal === "SIGTERM" ||
				signal === "SIGKILL" ||
				(code === 0 && signal === null);
			if (!expected) {
				console.warn(
					`[keep-awake] ${b} exited unexpectedly (code=${code}, signal=${signal})`,
				);
			}
			inhibitorProc = null;
			if (ctx?.ui) {
				ctx.ui.setStatus("keep-awake", undefined);
			}
		});
	};

	const stopInhibitor = (
		ctx?: Parameters<Parameters<typeof pi.on>[1]>[1],
	) => {
		activeSessions = Math.max(0, activeSessions - 1);
		if (activeSessions > 0 || !inhibitorProc) return;

		const p = inhibitorProc;
		inhibitorProc = null;
		terminateInhibitor(p);

		if (ctx?.ui) {
			ctx.ui.setStatus("keep-awake", undefined);
		}
	};

	const forceStopInhibitor = (
		ctx?: Parameters<Parameters<typeof pi.on>[1]>[1],
	) => {
		activeSessions = 0;
		if (!inhibitorProc) return;
		const p = inhibitorProc;
		inhibitorProc = null;
		terminateInhibitor(p);
		if (ctx?.ui) {
			ctx.ui.setStatus("keep-awake", undefined);
		}
	};

	pi.on("agent_start", async (_event, ctx) => {
		await startInhibitor(ctx);
	});

	pi.on("agent_end", async (_event, ctx) => {
		stopInhibitor(ctx);
	});

	pi.on("session_shutdown", async (_event, ctx) => {
		forceStopInhibitor(ctx);
	});

	process.on("exit", () => {
		if (inhibitorProc && inhibitorProc.pid) {
			terminateInhibitor(inhibitorProc);
		}
	});

	pi.registerCommand("keep-awake", {
		description: "Show keep-awake backend status",
		handler: async (_args, ctx) => {
			const state = inhibitorProc ? "active" : "inactive";
			const name = backend ?? "none";
			ctx.ui.notify(
				`Backend: ${name} | Status: ${state} | Sessions: ${activeSessions}`,
				"info",
			);
		},
	});
}
