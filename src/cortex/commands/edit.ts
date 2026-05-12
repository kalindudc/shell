import { defineCommand } from "citty";
import { Store, type Task } from "../store.ts";
import { Client, daemonUrl } from "../client.ts";

function parsePriority(raw: string): number {
  const n = Number.parseInt(raw, 10);
  if (!Number.isFinite(n) || n < 0 || String(n) !== raw.trim()) {
    console.error(
      `error: --priority must be a non-negative integer (0 = highest); got '${raw}'`,
    );
    process.exit(1);
  }
  return n;
}

export default defineCommand({
  meta: { name: "edit", description: "edit a task's title/body/priority" },
  args: {
    id: {
      type: "positional",
      required: true,
      description: "task id (see `cortex ls`)",
    },
    title: {
      type: "string",
      alias: "t",
      valueHint: "text",
      description: "new title",
    },
    body: {
      type: "string",
      alias: "b",
      valueHint: "text",
      description: "new body (use empty string to clear)",
    },
    priority: {
      type: "string",
      alias: "p",
      valueHint: "int",
      description: "new priority (non-negative integer; 0 = highest)",
    },
  },
  async run({ args }) {
    const id = Number.parseInt(args.id, 10);
    if (!Number.isFinite(id)) {
      console.error("error: id must be a number");
      process.exit(1);
    }
    const patch: { title?: string; body?: string | null; priority?: number } = {};
    if (args.title) patch.title = args.title;
    if (args.body !== undefined && args.body !== "") patch.body = args.body;
    if (args.priority) patch.priority = parsePriority(args.priority);
    if (Object.keys(patch).length === 0) {
      console.error("error: provide at least one of --title, --body, --priority");
      process.exit(1);
    }
    const url = daemonUrl();
    if (url) {
      try {
        const task = (await Client.editTask(url, id, patch)) as Task;
        console.log(`✓ edited [${task.id}] ${task.title}`);
        return;
      } catch (err) {
        console.error(`error: ${(err as Error).message}`);
        process.exit(1);
      }
    }
    const store = Store.open();
    try {
      const task = store.editTask(id, patch);
      console.log(`✓ edited [${task.id}] ${task.title}`);
    } catch (err) {
      console.error(`error: ${(err as Error).message}`);
      process.exit(1);
    } finally {
      store.close();
    }
  },
});
