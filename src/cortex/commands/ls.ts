import { defineCommand } from "citty";
import { Store, type TaskStatus, type Task } from "../store.ts";

const STATUSES: TaskStatus[] = ["open", "review", "blocked", "done"];

const useColor = (): boolean => !process.env.NO_COLOR && process.stdout.isTTY;
const c = (code: string, s: string) => (useColor() ? `\x1b[${code}m${s}\x1b[0m` : s);

const STATUS_BADGE: Record<TaskStatus, string> = {
  open: "○",
  review: "◐",
  blocked: "■",
  done: "✓",
};

const STATUS_COLOR: Record<TaskStatus, string> = {
  open: "37",
  review: "33",
  blocked: "31",
  done: "32",
};

export default defineCommand({
  meta: { name: "ls", description: "list tasks (grouped by lane, sorted by priority)" },
  args: {
    lane: {
      type: "string",
      alias: "l",
      valueHint: "name",
      description: "only show tasks in this lane",
    },
    status: {
      type: "string",
      alias: "s",
      valueHint: "open|review|blocked|done",
      description: `only show tasks with this status (one of: ${STATUSES.join(", ")})`,
    },
    json: {
      type: "boolean",
      default: false,
      description: "emit raw JSON instead of the grouped text view",
    },
  },
  run({ args }) {
    if (args.status && !STATUSES.includes(args.status as TaskStatus)) {
      console.error(`error: status must be one of ${STATUSES.join(",")}`);
      process.exit(1);
    }
    const store = Store.open();
    try {
      const rows = store.listTasks({
        lane: args.lane || undefined,
        status: (args.status as TaskStatus) || undefined,
      });
      if (args.json) {
        console.log(JSON.stringify(rows));
        return;
      }
      const byLane = new Map<string, Task[]>();
      for (const t of rows) {
        const list = byLane.get(t.lane) ?? [];
        list.push(t);
        byLane.set(t.lane, list);
      }
      if (byLane.size === 0) {
        console.log("(no tasks)");
        return;
      }
      for (const [lane, tasks] of byLane) {
        console.log(c("1", `\n${lane}`));
        for (const t of tasks) {
          const updates = store.listUpdates(t.id).length;
          const badge = c(STATUS_COLOR[t.status], STATUS_BADGE[t.status]);
          const idStr = c("90", `[${t.id}]`);
          const updStr = updates > 0 ? c("90", ` (${updates} updates)`) : "";
          console.log(`  ${idStr} ${badge} ${t.title}${updStr}`);
        }
      }
    } finally {
      store.close();
    }
  },
});
