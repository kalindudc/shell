import { defineCommand } from "citty";
import fs from "node:fs";
import { pidPath, urlPath } from "./../paths.ts";

function cleanupFiles(): void {
  fs.rmSync(pidPath(), { force: true });
  fs.rmSync(urlPath(), { force: true });
}

function isAlive(pid: number): boolean {
  try {
    // Signal 0 = liveness probe; doesn't deliver a signal.
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

export default defineCommand({
  meta: { name: "stop", description: "stop the cortex API server" },
  run() {
    const path = pidPath();
    if (!fs.existsSync(path)) {
      console.log("not running");
      return;
    }
    const raw = fs.readFileSync(path, "utf8").trim();
    const pid = Number.parseInt(raw, 10);
    if (!Number.isFinite(pid)) {
      console.log("pid file was corrupt; cleaned up");
      cleanupFiles();
      return;
    }
    if (!isAlive(pid)) {
      console.log("not running (cleaned up stale pid file)");
      cleanupFiles();
      return;
    }
    try {
      process.kill(pid, "SIGTERM");
    } catch (err) {
      // Race: process died between liveness check and SIGTERM. Treat as a no-op.
      const errno = (err as NodeJS.ErrnoException).errno;
      if (errno !== 3 /* ESRCH */) {
        console.error(`error: ${(err as Error).message}`);
        process.exit(1);
      }
    }
    cleanupFiles();
    console.log("✓ stopped");
  },
});
