/**
 * Embedded skill template — written into ~/.agents/skills/cortex/ on
 * `cortex init` (and wiped+rewritten on `cortex reset`).
 *
 * Why embedded: the CLI binary ships everything an agent needs to learn
 * cortex without a separate `cortex install-skill` step or an external
 * download. Each markdown file under src/cortex/skill/ is imported with
 * `with { type: "file" }`, which `bun build --compile` rewrites to a
 * `/$bunfs/...` virtual path; we read the bytes via `Bun.file(path)`.
 *
 * Identical idiom to UI_ASSETS in server.ts — same single-binary discipline.
 *
 * Idempotency: writeSkill() always overwrites. The skill is machine-
 * generated; documenting that in cli/init.md and cli/reset.md is the
 * load-bearing convention. Hand-edits are LOST on the next init/reset.
 */

import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import skillMdPath        from "./skill/SKILL.md"               with { type: "file" };
import cliInitPath        from "./skill/cli/init.md"            with { type: "file" };
import cliResetPath       from "./skill/cli/reset.md"           with { type: "file" };
import cliAddPath         from "./skill/cli/add.md"             with { type: "file" };
import cliUpdatePath      from "./skill/cli/update.md"          with { type: "file" };
import cliServePath       from "./skill/cli/serve.md"           with { type: "file" };
import recipeSessionPath  from "./skill/recipes/session-id.md"  with { type: "file" };

// Map relative path inside the skill dir → embedded blob path.
// The relPath becomes the on-disk name under skillDir().
const MANIFEST: Record<string, string> = {
  "SKILL.md":               skillMdPath,
  "cli/init.md":            cliInitPath,
  "cli/reset.md":           cliResetPath,
  "cli/add.md":             cliAddPath,
  "cli/update.md":          cliUpdatePath,
  "cli/serve.md":           cliServePath,
  "recipes/session-id.md":  recipeSessionPath,
};

/**
 * Default install location for the cortex skill.
 * `CORTEX_SKILL_DIR` env var overrides for test isolation — mirrors the
 * `CORTEX_DB` override in paths.ts so the integration test (which calls
 * `init`/`reset`) doesn't clobber the user's real ~/.agents/skills/cortex/.
 */
export function skillDir(): string {
  return (
    process.env.CORTEX_SKILL_DIR ??
    path.join(os.homedir(), ".agents", "skills", "cortex")
  );
}

/**
 * Write every embedded skill file into `targetDir`. Always overwrites
 * (the skill is machine-generated; that's the contract).
 *
 * `targetDir` is overridable so tests can write into a tmp dir.
 */
export async function writeSkill(targetDir: string = skillDir()): Promise<void> {
  fs.mkdirSync(targetDir, { recursive: true });
  for (const [rel, embedPath] of Object.entries(MANIFEST)) {
    const target = path.join(targetDir, rel);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    const bytes = await Bun.file(embedPath).bytes();
    fs.writeFileSync(target, bytes);
  }
}
