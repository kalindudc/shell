import { defineCommand } from "citty";
import { Store } from "../store.ts";

export default defineCommand({
  meta: { name: "show", description: "show a task and its updates" },
  args: {
    id: {
      type: "positional",
      required: true,
      description: "task id",
    },
    json: {
      type: "boolean",
      default: false,
      description: "emit raw JSON instead of the formatted view",
    },
  },
  run({ args }) {
    const id = Number.parseInt(args.id, 10);
    if (!Number.isFinite(id)) {
      console.error("error: id must be a number");
      process.exit(1);
    }
    const store = Store.open();
    try {
      const task = store.getTask(id);
      if (!task) {
        console.error(`task ${id} not found`);
        process.exit(1);
      }
      const updates = store.listUpdates(id);
      if (args.json) {
        console.log(JSON.stringify({ task, updates }));
        return;
      }
      console.log(`[${task.id}] ${task.title}`);
      console.log(`  lane:     ${task.lane}`);
      console.log(`  status:   ${task.status}`);
      console.log(`  priority: ${task.priority}`);
      console.log(`  created:  ${new Date(task.created).toISOString()}`);
      console.log(`  updated:  ${new Date(task.updated).toISOString()}`);
      if (task.body) {
        console.log(`\n${task.body}`);
      }
      if (updates.length > 0) {
        console.log(`\nupdates:`);
        for (const u of updates) {
          const ts = new Date(u.created).toISOString();
          console.log(`  [${u.severity}] ${ts} ${u.author}: ${u.summary}`);
          if (u.body) {
            for (const line of u.body.split("\n")) {
              console.log(`    ${line}`);
            }
          }
        }
      }
    } finally {
      store.close();
    }
  },
});
