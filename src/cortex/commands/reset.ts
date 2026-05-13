import { defineCommand } from "citty";
import readline from "node:readline";
import fs from "node:fs";
import { Store } from "../store.ts";
import { dbPath, pidPath, urlPath, ensureConfigDir } from "../paths.ts";
import { writeSkill, skillDir } from "../skill.ts";

const CONFIRM = "RESET";

function prompt(question: string): Promise<string> {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer);
    });
  });
}

function readPid(): number | null {
  if (!fs.existsSync(pidPath())) return null;
  const pid = Number.parseInt(fs.readFileSync(pidPath(), "utf8").trim(), 10);
  return Number.isFinite(pid) ? pid : null;
}

function isAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

/**
 * Stop the daemon if running. Idempotent: returns true on a successful stop,
 * false if no live daemon was found. Always cleans up the pid/url files.
 */
async function stopDaemonIfRunning(): Promise<boolean> {
  const pid = readPid();
  let stopped = false;
  if (pid !== null && isAlive(pid)) {
    try {
      process.kill(pid, "SIGTERM");
      stopped = true;
      // Give the daemon's SIGTERM handler ~1s to exit cleanly and remove its
      // own pid/url files. If it doesn't, we'll force-remove below.
      for (let i = 0; i < 20; i++) {
        if (!isAlive(pid)) break;
        await Bun.sleep(50);
      }
    } catch {
      /* ignore — we'll wipe the files regardless */
    }
  }
  // Force-cleanup any lingering daemon state files.
  for (const p of [pidPath(), urlPath()]) {
    try {
      fs.rmSync(p, { force: true });
    } catch {
      /* ignore */
    }
  }
  return stopped;
}

export default defineCommand({
  meta: {
    name: "reset",
    description:
      "wipe the cortex database and re-initialize (requires typing RESET to confirm)",
  },
  async run() {
    const db = dbPath();
    const livePid =
      readPid() !== null && isAlive(readPid()!) ? readPid() : null;

    console.log(`This will:`);
    if (livePid !== null) {
      console.log(`  • stop the running cortex daemon (pid ${livePid})`);
    }
    console.log(`  • delete ${db}`);
    console.log(`  • delete ${db}-wal, ${db}-shm (SQLite WAL sidecars, if present)`);
    console.log(`  • delete ${pidPath()}, ${urlPath()} (daemon state, if present)`);
    console.log(`  • wipe and regenerate the cortex skill at ${skillDir()}`);
    console.log(`  • re-initialize an empty database with the default 'now' lane`);
    const answer = await prompt(`Type ${CONFIRM} to confirm: `);
    if (answer.trim() !== CONFIRM) {
      console.log("aborted (input did not match RESET)");
      process.exit(1);
    }

    // 1. Stop daemon (idempotent; cleans up pid/url files).
    const stopped = await stopDaemonIfRunning();
    if (stopped) console.log("✓ stopped daemon");

    // 2. Wipe DB + WAL sidecars.
    for (const p of [db, `${db}-wal`, `${db}-shm`]) {
      try {
        fs.rmSync(p, { force: true });
      } catch {
        /* ignore */
      }
    }
    console.log("✓ wiped database files");

    // 3. Re-init: opens a fresh DB, runs migrations, seeds 'now' lane.
    ensureConfigDir();
    const s = Store.open();
    s.close();
    console.log(`✓ re-initialized ${db}`);

    // 4. Wipe + regenerate the skill dir. We rmSync first (rather than just
    // overwriting via writeSkill) so files removed in a binary upgrade are
    // dropped, not stranded. Hand-edits are LOST — documented in cli/reset.md.
    fs.rmSync(skillDir(), { recursive: true, force: true });
    await writeSkill();
    console.log(`✓ regenerated skill at ${skillDir()}`);

    console.log("✓ reset complete");
  },
});
