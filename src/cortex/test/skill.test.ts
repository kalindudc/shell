import { test, expect, describe, beforeAll, afterAll } from "bun:test";
import path from "node:path";
import os from "node:os";
import fs from "node:fs";
import { writeSkill } from "../skill.ts";

// The skill template is embedded in the cortex binary and self-installed at
// ~/.agents/skills/cortex/. Tests use CORTEX_SKILL_DIR (and the function's
// override parameter) to write into a tmp dir instead of the user's real
// home, so the assertions are reproducible and do not corrupt user data.

let tmpDir: string;

beforeAll(() => {
  tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "cortex-skill-"));
});

afterAll(() => {
  fs.rmSync(tmpDir, { recursive: true, force: true });
});

describe("writeSkill", () => {
  test("writes SKILL.md with valid YAML frontmatter (name + description)", async () => {
    await writeSkill(tmpDir);
    const skillPath = path.join(tmpDir, "SKILL.md");
    expect(fs.existsSync(skillPath)).toBe(true);
    const text = fs.readFileSync(skillPath, "utf8");
    // Frontmatter is the first block bounded by `---` lines.
    expect(text.startsWith("---")).toBe(true);
    const closingIndex = text.indexOf("---", 3);
    expect(closingIndex).toBeGreaterThan(0);
    const frontmatter = text.slice(3, closingIndex);
    expect(frontmatter).toMatch(/name:\s*cortex/);
    // Verbatim description from Plan 3.
    expect(frontmatter).toMatch(/description:\s*Personal task tracker/);
  });

  test("writes every cli/*.md and recipes/session-id.md, each > 200 bytes", async () => {
    await writeSkill(tmpDir);
    const expected = [
      "cli/init.md",
      "cli/reset.md",
      "cli/add.md",
      "cli/update.md",
      "cli/serve.md",
      "recipes/session-id.md",
    ];
    for (const rel of expected) {
      const abs = path.join(tmpDir, rel);
      expect(fs.existsSync(abs)).toBe(true);
      const stat = fs.statSync(abs);
      expect(stat.size).toBeGreaterThan(200);
    }
  });

  test("cli/update.md contains the literal 'REQUIRED' warning", async () => {
    await writeSkill(tmpDir);
    const text = fs.readFileSync(path.join(tmpDir, "cli/update.md"), "utf8");
    // Agents grep for this exact word; the citty error message also contains
    // the flag name. The skill is the canonical reference.
    expect(text).toContain("REQUIRED");
  });

  test("re-running writeSkill is idempotent (overwrites; no extra files)", async () => {
    await writeSkill(tmpDir);
    const firstListing = listing(tmpDir).sort();
    await writeSkill(tmpDir);
    const secondListing = listing(tmpDir).sort();
    expect(secondListing).toEqual(firstListing);
  });
});

function listing(dir: string): string[] {
  const out: string[] = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      out.push(...listing(full));
    } else {
      out.push(full);
    }
  }
  return out;
}
