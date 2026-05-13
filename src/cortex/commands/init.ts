import { defineCommand } from "citty";
import { Store } from "../store.ts";
import { dbPath, ensureConfigDir } from "../paths.ts";
import { writeSkill, skillDir } from "../skill.ts";

export default defineCommand({
  meta: { name: "init", description: "initialize the cortex database" },
  async run() {
    ensureConfigDir();
    const s = Store.open();
    s.close();
    // Self-install the skill template so coding agents have an authoritative
    // recipe (especially session-id + the REQUIRED --as warning) on disk.
    // Always overwrites — the skill is machine-generated; hand-edits are LOST.
    await writeSkill();
    console.log(`✓ skill written to ${skillDir()}`);
    console.log(`✓ initialized ${dbPath()}`);
  },
});
