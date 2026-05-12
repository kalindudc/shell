import { defineCommand } from "citty";
import readline from "node:readline";
import { Store } from "../store.ts";
import { Client, daemonUrl } from "../client.ts";

function prompt(question: string): Promise<string> {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer);
    });
  });
}

export default defineCommand({
  meta: { name: "rm", description: "remove a task (and its updates, via cascade)" },
  args: {
    id: {
      type: "positional",
      required: true,
      description: "task id",
    },
    force: {
      type: "boolean",
      alias: "f",
      default: false,
      description: "skip the y/N confirmation prompt",
    },
  },
  async run({ args }) {
    const id = Number.parseInt(args.id, 10);
    if (!Number.isFinite(id)) {
      console.error("error: id must be a number");
      process.exit(1);
    }
    if (!args.force) {
      const answer = await prompt(`delete task ${id}? [y/N] `);
      if (answer.trim().toLowerCase() !== "y") {
        console.log("aborted");
        return;
      }
    }
    const url = daemonUrl();
    if (url) {
      try {
        await Client.removeTask(url, id);
        console.log(`✓ removed task ${id}`);
        return;
      } catch (err) {
        console.error(`error: ${(err as Error).message}`);
        process.exit(1);
      }
    }
    const store = Store.open();
    try {
      store.removeTask(id);
      console.log(`✓ removed task ${id}`);
    } catch (err) {
      console.error(`error: ${(err as Error).message}`);
      process.exit(1);
    } finally {
      store.close();
    }
  },
});
