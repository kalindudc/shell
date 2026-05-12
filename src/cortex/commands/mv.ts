import { defineCommand } from "citty";
import { Store, type Task } from "../store.ts";
import { Client, daemonUrl } from "../client.ts";

export default defineCommand({
  meta: { name: "mv", description: "move a task to a different lane (auto-creates lane if missing)" },
  args: {
    id: {
      type: "positional",
      required: true,
      description: "task id",
    },
    lane: {
      type: "positional",
      required: true,
      description: "destination lane name",
    },
  },
  async run({ args }) {
    const id = Number.parseInt(args.id, 10);
    if (!Number.isFinite(id)) {
      console.error("error: id must be a number");
      process.exit(1);
    }
    const url = daemonUrl();
    if (url) {
      try {
        const task = (await Client.moveTask(url, id, args.lane)) as Task;
        console.log(`✓ [${task.id}] → ${task.lane}`);
        return;
      } catch (err) {
        console.error(`error: ${(err as Error).message}`);
        process.exit(1);
      }
    }
    const store = Store.open();
    try {
      const task = store.moveTask(id, args.lane);
      console.log(`✓ [${task.id}] → ${task.lane}`);
    } catch (err) {
      console.error(`error: ${(err as Error).message}`);
      process.exit(1);
    } finally {
      store.close();
    }
  },
});
