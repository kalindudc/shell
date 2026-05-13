import { defineCommand } from "citty";
import {
  Store,
  validateAuthorTag,
  type TaskStatus,
  type Update,
} from "../store.ts";
import { Client, daemonUrl } from "../client.ts";

const STATUSES: TaskStatus[] = ["open", "review", "blocked", "done"];

export default defineCommand({
  meta: {
    name: "update",
    description: "post an update on a task (and optionally change its status)",
  },
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
      description: `short summary, max 1024 chars`,
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
    as: {
      type: "string",
      alias: "author",
      required: true,
      valueHint: "id",
      description:
        "REQUIRED attribution tag for this update. Generate once per session via ${ROLE}-$(openssl rand -hex 4); see ~/.agents/skills/cortex/recipes/session-id.md.",
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
    // citty `required: true` rejects missing --as at parse time, but we
    // also validate the value here (defense in depth: matches Store +
    // server validation, single error format).
    let author: string;
    try {
      author = validateAuthorTag(args.as);
    } catch (err) {
      console.error(`error: ${(err as Error).message}`);
      process.exit(1);
    }
    const updatePayload = {
      author,
      summary: args.message,
      body: args.body || null,
    };
    const url = daemonUrl();
    if (url) {
      try {
        const u = (await Client.addUpdate(url, id, updatePayload)) as Update;
        console.log(`✓ update [${u.id}] posted on task ${id}`);
        if (args.status) {
          // Pass author through so the server's audit-trail row inside
          // setStatus is attributed to the same session, not the cascade.
          await Client.setStatus(url, id, args.status, author);
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
        store.setStatus(id, args.status as TaskStatus, { author });
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
