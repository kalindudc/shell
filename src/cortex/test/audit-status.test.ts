import { test, expect, describe, beforeAll, afterAll } from "bun:test";
import path from "node:path";
import os from "node:os";
import fs from "node:fs";
import { Store } from "../store.ts";

// Plan 3: every setStatus call writes an audit-trail row in `updates`
// alongside the actual status mutation (in the same transaction). This makes
// parallel-agent status oscillation visible as inbox history rather than
// silently overwriting the previous status.

const BUN = process.execPath;
const ROOT = path.resolve(import.meta.dir, "..");
const CLI = path.join(ROOT, "cli.ts");

let tmpDir: string;
let dbPath: string;
let skillDir: string;

beforeAll(() => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "cortex-audit-"));
  dbPath = path.join(tmpDir, "cortex.db");
  skillDir = path.join(tmpDir, "skill");
});

afterAll(() => {
  fs.rmSync(tmpDir, { recursive: true, force: true });
});

async function run(...args: string[]): Promise<{
  code: number;
  stdout: string;
  stderr: string;
}> {
  const proc = Bun.spawn([BUN, CLI, ...args], {
    env: {
      ...process.env,
      CORTEX_DB: dbPath,
      CORTEX_SKILL_DIR: skillDir,
      NO_COLOR: "1",
    },
    cwd: ROOT,
    stdout: "pipe",
    stderr: "pipe",
  });
  await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);
  return {
    code: await proc.exited,
    stdout: "",
    stderr: "",
  };
}

describe("audit-trail status rows", () => {
  test("update -s review writes message + audit-trail row, both attributed", async () => {
    let r = await run("init");
    expect(r.code).toBe(0);
    r = await run("add", "audit-target");
    expect(r.code).toBe(0);

    r = await run("update", "1", "-s", "review", "-m", "ready", "--as", "a-1");
    expect(r.code).toBe(0);

    const s = Store.open(dbPath);
    const rows = s.listUpdates(1);
    s.close();
    expect(rows.length).toBe(2);
    // Both rows attributed to the same session.
    expect(rows.every((u) => u.author === "a-1")).toBe(true);
    // One row carries the message text the user typed, the other carries
    // the audit-trail marker.
    const summaries = rows.map((u) => u.summary).sort();
    expect(summaries).toEqual(["ready", "status \u2192 review"].sort());
  });

  test("a second status change appends another pair, status updates, audit chronological", async () => {
    let r = await run("update", "1", "-s", "blocked", "-m", "stuck", "--as", "a-2");
    expect(r.code).toBe(0);

    const s = Store.open(dbPath);
    const rows = s.listUpdates(1);
    const task = s.getTask(1);
    s.close();
    // 2 from the first status change + 2 from the second.
    expect(rows.length).toBe(4);
    expect(task?.status).toBe("blocked");
    // Last two rows attributed to a-2.
    const last2 = rows.slice(-2);
    expect(last2.every((u) => u.author === "a-2")).toBe(true);
    const last2Summaries = last2.map((u) => u.summary).sort();
    expect(last2Summaries).toEqual(["status \u2192 blocked", "stuck"].sort());
  });

  test("Store.addUpdate accepts 1024-char summary directly; rejects 1025", () => {
    const s = Store.open(":memory:");
    const t = s.addTask({ title: "x" });
    expect(() =>
      s.addUpdate({ task_id: t.id, author: "a", summary: "x".repeat(1024) }),
    ).not.toThrow();
    expect(() =>
      s.addUpdate({ task_id: t.id, author: "a", summary: "x".repeat(1025) }),
    ).toThrow(/summary too long/);
    s.close();
  });
});
