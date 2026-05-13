import { test, expect, describe, beforeAll, afterAll } from "bun:test";
import path from "node:path";
import os from "node:os";
import fs from "node:fs";
import { Store, validateAuthorTag } from "../store.ts";

// ---------- pure-unit assertions on the validator ----------
//
// validateAuthorTag is the single chokepoint enforced from three sites:
//   1. CLI flag-parse (commands/update.ts) — defense in depth
//   2. HTTP handler (server.ts) — early 400 rejection
//   3. Store.addUpdate — final guard at the DB layer
// Tests below pin the contract (no newlines, max 80 chars).

describe("validateAuthorTag", () => {
  test("accepts a typical session-id tag and trims whitespace", () => {
    expect(validateAuthorTag("planner-7f3a")).toBe("planner-7f3a");
    expect(validateAuthorTag("  spaced-tag  ")).toBe("spaced-tag");
  });

  test("rejects embedded newlines (would corrupt per-line SSE/log rendering)", () => {
    expect(() => validateAuthorTag("x\ny")).toThrow(/newlines/);
  });

  test("rejects tags > 80 chars (sanity bound)", () => {
    expect(() => validateAuthorTag("a".repeat(81))).toThrow(/max 80/);
    // Boundary: exactly 80 chars must succeed.
    expect(() => validateAuthorTag("a".repeat(80))).not.toThrow();
  });
});

// ---------- CLI integration: --as is REQUIRED ----------
//
// citty's `required: true` rejects missing values at parse time. The CLI
// must exit non-zero with an error mentioning the flag (so agents can grep
// their own stderr to discover the requirement).

const BUN = process.execPath;
const ROOT = path.resolve(import.meta.dir, "..");
const CLI = path.join(ROOT, "cli.ts");

let tmpDir: string;
let dbPath: string;
let skillDir: string;

beforeAll(() => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "cortex-author-"));
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
  const [stdout, stderr] = await Promise.all([
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);
  const code = await proc.exited;
  return { code, stdout, stderr };
}

describe("cortex update --as integration", () => {
  test("missing --as exits non-zero with an error mentioning the flag", async () => {
    let r = await run("init");
    expect(r.code).toBe(0);
    r = await run("add", "test task");
    expect(r.code).toBe(0);

    // Forget --as on purpose. citty should reject.
    r = await run("update", "1", "-m", "x");
    expect(r.code).not.toBe(0);
    // Either citty's own message or our explicit error: must mention `as`
    // or `author` (so agents can grep their stderr to discover the flag).
    const combined = (r.stderr + r.stdout).toLowerCase();
    expect(combined).toMatch(/as|author/);
  });

  test("--as <id> stores the row attributed to that id", async () => {
    // Fresh DB for this assertion.
    fs.rmSync(dbPath, { force: true });
    let r = await run("init");
    expect(r.code).toBe(0);
    r = await run("add", "attribution task");
    expect(r.code).toBe(0);

    r = await run("update", "1", "-m", "hello", "--as", "planner-abc");
    expect(r.code).toBe(0);

    // Read back via Store directly (no daemon).
    const s = Store.open(dbPath);
    const rows = s.listUpdates(1);
    s.close();
    // Exactly one row (no status change → no audit-trail row).
    expect(rows.length).toBe(1);
    expect(rows[0]?.author).toBe("planner-abc");
    expect(rows[0]?.summary).toBe("hello");
  });
});
