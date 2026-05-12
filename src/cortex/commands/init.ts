import { defineCommand } from "citty";
import { Store } from "../store.ts";
import { dbPath, ensureConfigDir } from "../paths.ts";

export default defineCommand({
  meta: { name: "init", description: "initialize the cortex database" },
  run() {
    ensureConfigDir();
    const s = Store.open();
    s.close();
    console.log(`✓ initialized ${dbPath()}`);
  },
});
