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
  meta: { name: "add", description: "add a task" },
  args: {
    title: {
      type: "positional",
      required: true,
      description: "task title (quote it if it has spaces)",
    },
    lane: {
      type: "string",
      alias: "l",
      default: "now",
      valueHint: "name",
      description: "lane to put the task in (auto-created if missing)",
    },
    priority: {
      type: "string",
      alias: "p",
      default: "1",
      valueHint: "int",
      description: "priority as a non-negative integer; 0 = highest",
    },
    body: {
      type: "string",
      alias: "b",
      valueHint: "text",
      description: "longer description shown by `cortex show`",
    },
  },
  async run({ args }) {
    const payload = {
      title: args.title,
      lane: args.lane,
      priority: parsePriority(args.priority),
      body: args.body || null,
    };
    const url = daemonUrl();
    if (url) {
      try {
        const task = (await Client.addTask(url, payload)) as Task;
        console.log(`[${task.id}] ${task.title}`);
        return;
      } catch (err) {
        console.error(`error: ${(err as Error).message}`);
        process.exit(1);
      }
    }
    const store = Store.open();
    try {
      const task = store.addTask(payload);
      console.log(`[${task.id}] ${task.title}`);
    } catch (err) {
      console.error(`error: ${(err as Error).message}`);
      process.exit(1);
    } finally {
      store.close();
    }
  },
});
