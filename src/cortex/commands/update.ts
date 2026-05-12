import { defineCommand } from "citty";
import { Store, type TaskStatus, type Update } from "../store.ts";
import { Client, daemonUrl } from "../client.ts";

const STATUSES: TaskStatus[] = ["open", "review", "blocked", "done"];

export default defineCommand({
  meta: { name: "update", description: "post an update on a task (and optionally change its status)" },
  args: {
    id: {
      type: "positional",
      required: true,
      description: "task id (see `cortex ls`)",
    },
    message: {
      type: "string",
      alias: "m",
      required: true,
      valueHint: "text",
      description: `short summary, max 200 chars`,
    },
    status: {
      type: "string",
      alias: "s",
      valueHint: "open|review|blocked|done",
      description: `change task status to one of: ${STATUSES.join(", ")}`,
    },
    body: {
      type: "string",
      alias: "b",
      valueHint: "text",
      description: "longer detail shown in `cortex show`",
    },
  },
  async run({ args }) {
    const id = Number.parseInt(args.id, 10);
    if (!Number.isFinite(id)) {
      console.error("error: id must be a number");
      process.exit(1);
    }
    if (args.status && !STATUSES.includes(args.status as TaskStatus)) {
      console.error(`error: status must be one of ${STATUSES.join(",")}`);
      process.exit(1);
    }
    const updatePayload = {
      author: process.env.USER ?? "human",
      summary: args.message,
      body: args.body || null,
    };
    const url = daemonUrl();
    if (url) {
      try {
        const u = (await Client.addUpdate(url, id, updatePayload)) as Update;
        console.log(`✓ update [${u.id}] posted on task ${id}`);
        if (args.status) {
          await Client.setStatus(url, id, args.status);
          console.log(`✓ status → ${args.status}`);
        }
        return;
      } catch (err) {
        console.error(`error: ${(err as Error).message}`);
        process.exit(1);
      }
    }
    const store = Store.open();
    try {
      const update = store.addUpdate({ task_id: id, ...updatePayload });
      console.log(`✓ update [${update.id}] posted on task ${id}`);
      if (args.status) {
        store.setStatus(id, args.status as TaskStatus);
        console.log(`✓ status → ${args.status}`);
      }
    } catch (err) {
      console.error(`error: ${(err as Error).message}`);
      process.exit(1);
    } finally {
      store.close();
    }
  },
});
