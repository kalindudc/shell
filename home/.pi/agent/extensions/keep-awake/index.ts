/**
 * Keep Awake Extension
 *
 * Prevents the system from sleeping while the pi agent is actively working.
 * Supports macOS (caffeinate) and Linux (systemd-inhibit), with optional
 * keepawake binary as the preferred cross-platform backend.
 *
 * Sleep inhibition starts on agent_start and ends on agent_end or
 * session_shutdown.
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
		return spawn("keepawake", ["-i", "-d"], { stdio: "ignore" });
	}

	if (backend === "caffeinate") {
		return spawn("caffeinate", ["-i", "-d"], { stdio: "ignore" });
	}

	if (backend === "systemd-inhibit") {
		return spawn(
			"systemd-inhibit",
			[
				"--what=idle:sleep",
				"--who=pi",
				"--why=Active pi agent session",
				"--mode=block",
				"sleep",
				"99999999",
			],
			{ stdio: "ignore" },
		);
	}

	return null;
}

export default function (pi: ExtensionAPI): void {
	const backendPromise = resolveBackend();
	let backend: Backend = null;
	backendPromise.then((b) => {
		backend = b;
	});

	let proc: ChildProcess | null = null;
	let notifiedMissing = false;

	const startInhibitor = async (ctx?: Parameters<Parameters<typeof pi.on>[1]>[1]) => {
		const b = await backendPromise;
		if (!b) {
			if (!notifiedMissing) {
				console.warn(
					"[keep-awake] No supported backend found. Install keepawake or use macOS/Linux with built-in tools.",
				);
				notifiedMissing = true;
			}
			return;
		}

		if (proc) return; // already running

		proc = spawnInhibitor(b);
		if (!proc) return;

		if (ctx?.ui) {
			const theme = ctx.ui.theme;
			ctx.ui.setStatus("keep-awake", theme.fg("warning", "☕") + theme.fg("dim", " awake"));
		}

		proc.on("error", (err) => {
			console.error(`[keep-awake] ${b} failed to spawn:`, err.message);
			proc = null;
			if (ctx?.ui) {
				ctx.ui.setStatus("keep-awake", undefined);
			}
		});

		proc.on("exit", (code, signal) => {
			if (code !== 0 && signal !== "SIGTERM" && signal !== null) {
				console.warn(`[keep-awake] ${b} exited unexpectedly (code=${code}, signal=${signal})`);
			}
			proc = null;
			if (ctx?.ui) {
				ctx.ui.setStatus("keep-awake", undefined);
			}
		});
	};

	const stopInhibitor = (ctx?: Parameters<Parameters<typeof pi.on>[1]>[1]) => {
		if (proc) {
			proc.kill();
			proc = null;
		}
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
		stopInhibitor(ctx);
	});

	pi.registerCommand("keep-awake", {
		description: "Show keep-awake backend status",
		handler: async (_args, ctx) => {
			const state = proc ? "active" : "inactive";
			const name = backend ?? "none";
			ctx.ui.notify(`Backend: ${name} | Status: ${state}`, "info");
		},
	});
}
