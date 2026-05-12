import { test, expect, beforeAll, afterAll } from "bun:test";
import path from "node:path";
import os from "node:os";
import fs from "node:fs";

const BUN = process.execPath;
const ROOT = path.resolve(import.meta.dir, "..");
const CLI = path.join(ROOT, "cli.ts");

let tmpDir: string;
let dbPath: string;

beforeAll(() => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "cortex-cli-"));
  dbPath = path.join(tmpDir, "cortex.db");
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
    env: { ...process.env, CORTEX_DB: dbPath, NO_COLOR: "1" },
    cwd: ROOT,
    stdout: "pipe",
    stderr: "pipe",
  });
  const [stdout, stderr] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);
  const code = await proc.exited;
  return { code, stdout, stderr };
}

// Helper that pipes stdin to a CLI invocation.
async function runWithInput(
  input: string,
  ...args: string[]
): Promise<{ code: number; stdout: string; stderr: string }> {
  const proc = Bun.spawn([BUN, CLI, ...args], {
    env: { ...process.env, CORTEX_DB: dbPath, NO_COLOR: "1" },
    cwd: ROOT,
    stdin: "pipe",
    stdout: "pipe",
    stderr: "pipe",
  });
  proc.stdin.write(input);
  await proc.stdin.end();
  const [stdout, stderr] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);
  const code = await proc.exited;
  return { code, stdout, stderr };
}

test("reset wipes and re-inits when RESET is typed; aborts otherwise", async () => {
  // Seed some state.
  let r = await run("init");
  expect(r.code).toBe(0);
  r = await run("add", "keepable");
  expect(r.code).toBe(0);
  r = await run("ls", "--json");
  expect(JSON.parse(r.stdout).length).toBe(1);

  // Wrong input aborts and leaves state intact.
  r = await runWithInput("no\n", "reset");
  expect(r.code).toBe(1);
  expect(r.stdout).toContain("aborted");
  r = await run("ls", "--json");
  expect(JSON.parse(r.stdout).length).toBe(1);

  // Correct input wipes + re-inits.
  r = await runWithInput("RESET\n", "reset");
  expect(r.code).toBe(0);
  expect(r.stdout).toContain("reset complete");
  r = await run("ls", "--json");
  expect(JSON.parse(r.stdout)).toEqual([]);
  // 'now' lane is seeded fresh.
  r = await run("lane", "ls", "--json");
  const lanes = JSON.parse(r.stdout);
  expect(lanes.map((l: { name: string }) => l.name)).toEqual(["now"]);
});

test("CLI round-trip: init → add → ls → update → edit → mv → rm", async () => {
  // init
  let r = await run("init");
  expect(r.code).toBe(0);
  expect(r.stdout).toContain("initialized");

  // add two tasks
  r = await run("add", "task one", "-p", "0");
  expect(r.code).toBe(0);
  expect(r.stdout).toMatch(/^\[1\] task one/);

  r = await run("add", "task two", "-l", "now");
  expect(r.code).toBe(0);
  expect(r.stdout).toMatch(/^\[2\] task two/);

  // ls --json shows 2 tasks
  r = await run("ls", "--json");
  expect(r.code).toBe(0);
  const list1 = JSON.parse(r.stdout);
  expect(Array.isArray(list1)).toBe(true);
  expect(list1.length).toBe(2);

  // update with status change
  r = await run("update", "1", "-m", "in review now", "-s", "review");
  expect(r.code).toBe(0);
  expect(r.stdout).toContain("update");
  expect(r.stdout).toContain("status");

  // status filter shows only the open one
  r = await run("ls", "--status", "open", "--json");
  expect(r.code).toBe(0);
  const openList = JSON.parse(r.stdout);
  expect(openList.length).toBe(1);
  expect(openList[0].id).toBe(2);

  // edit task 1
  r = await run("edit", "1", "-t", "task one renamed", "-p", "5");
  expect(r.code).toBe(0);

  // add a new lane and mv
  r = await run("lane", "add", "later", "-c", "#666");
  expect(r.code).toBe(0);
  r = await run("mv", "2", "later");
  expect(r.code).toBe(0);
  expect(r.stdout).toContain("later");

  // show task 1 as JSON
  r = await run("show", "1", "--json");
  expect(r.code).toBe(0);
  const show = JSON.parse(r.stdout);
  expect(show.task.title).toBe("task one renamed");
  expect(show.task.status).toBe("review");
  expect(show.updates.length).toBe(1);

  // rm both with -f
  r = await run("rm", "1", "-f");
  expect(r.code).toBe(0);
  r = await run("rm", "2", "-f");
  expect(r.code).toBe(0);

  // final ls is empty
  r = await run("ls", "--json");
  expect(r.code).toBe(0);
  expect(JSON.parse(r.stdout)).toEqual([]);
});
