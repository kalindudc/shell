/**
 * Agents Context Extension
 *
 * Bridges ~/.agents/AGENTS.md into Pi's system prompt at each agent start.
 *
 * Pi does not discover ~/.agents/AGENTS.md natively. This extension
 * reads the shared protocol file and appends it to the system prompt
 * via the before_agent_start event.
 *
 * Survives compaction (system prompt is never compacted).
 * If ~/.agents/AGENTS.md does not exist, logs a warning and skips.
 */

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { readFileSync, existsSync } from "fs";
import { join } from "path";

export default function (pi: ExtensionAPI) {
  const agentsPath = join(process.env.HOME ?? "", ".agents", "AGENTS.md");

  pi.on("before_agent_start", async (event, _ctx) => {
    if (!existsSync(agentsPath)) {
      console.warn(
        `[agents-context] ~/.agents/AGENTS.md not found at ${agentsPath}. Skipping.`,
      );
      return;
    }

    const content = readFileSync(agentsPath, "utf-8");

    return {
      systemPrompt:
        event.systemPrompt +
        `\n\n<agents-protocol>\n${content}\n</agents-protocol>`,
    };
  });
}
