import { defineCommand } from "citty";
import { Store, type Lane } from "../store.ts";
import { Client, daemonUrl } from "../client.ts";

const add = defineCommand({
  meta: { name: "add", description: "create a lane" },
  args: {
    name: {
      type: "positional",
      required: true,
      description: "lane name (also the FK target for tasks)",
    },
    color: {
      type: "string",
      alias: "c",
      valueHint: "#hex",
      description: "display color hex (e.g. #fe8019); used by the dashboard",
    },
  },
  async run({ args }) {
    const payload = {
      name: args.name,
      color: args.color || null,
    };
    const url = daemonUrl();
    if (url) {
      try {
        const lane = (await Client.addLane(url, payload)) as Lane;
        console.log(`✓ lane ${lane.name} created`);
        return;
      } catch (err) {
        console.error(`error: ${(err as Error).message}`);
        process.exit(1);
      }
    }
    const store = Store.open();
    try {
      const lane = store.addLane(payload);
      console.log(`✓ lane ${lane.name} created`);
    } catch (err) {
      console.error(`error: ${(err as Error).message}`);
      process.exit(1);
    } finally {
      store.close();
    }
  },
});

const ls = defineCommand({
  meta: { name: "ls", description: "list lanes" },
  args: {
    json: {
      type: "boolean",
      default: false,
      description: "emit raw JSON instead of a table",
    },
  },
  run({ args }) {
    const store = Store.open();
    try {
      const lanes = store.listLanes();
      if (args.json) {
        console.log(JSON.stringify(lanes));
        return;
      }
      console.table(
        lanes.map((l) => ({
          name: l.name,
          color: l.color ?? "",
        })),
      );
    } finally {
      store.close();
    }
  },
});

const edit = defineCommand({
  meta: { name: "edit", description: "edit a lane" },
  args: {
    name: {
      type: "positional",
      required: true,
      description: "current lane name",
    },
    color: {
      type: "string",
      alias: "c",
      valueHint: "#hex",
      description: "new display color",
    },
    rename: {
      type: "string",
      valueHint: "new-name",
      description: "rename the lane (cascades to all tasks via FK)",
    },
  },
  async run({ args }) {
    const fields: {
      color?: string | null;
      rename?: string;
    } = {};
    if (args.color) fields.color = args.color;
    if (args.rename) fields.rename = args.rename;
    if (Object.keys(fields).length === 0) {
      console.error("error: provide at least one of --color, --rename");
      process.exit(1);
    }
    const url = daemonUrl();
    if (url) {
      try {
        const lane = (await Client.editLane(url, args.name, fields)) as Lane;
        console.log(`✓ lane ${lane.name} updated`);
        return;
      } catch (err) {
        console.error(`error: ${(err as Error).message}`);
        process.exit(1);
      }
    }
    const store = Store.open();
    try {
      const lane = store.editLane(args.name, fields);
      console.log(`✓ lane ${lane.name} updated`);
    } catch (err) {
      console.error(`error: ${(err as Error).message}`);
      process.exit(1);
    } finally {
      store.close();
    }
  },
});

const rm = defineCommand({
  meta: { name: "rm", description: "remove an empty lane (refuses 'now' or non-empty lanes)" },
  args: {
    name: {
      type: "positional",
      required: true,
      description: "lane name",
    },
  },
  async run({ args }) {
    const url = daemonUrl();
    if (url) {
      try {
        await Client.removeLane(url, args.name);
        console.log(`✓ lane ${args.name} removed`);
        return;
      } catch (err) {
        console.error(`error: ${(err as Error).message}`);
        process.exit(1);
      }
    }
    const store = Store.open();
    try {
      store.removeLane(args.name);
      console.log(`✓ lane ${args.name} removed`);
    } catch (err) {
      console.error(`error: ${(err as Error).message}`);
      process.exit(1);
    } finally {
      store.close();
    }
  },
});

export default defineCommand({
  meta: { name: "lane", description: "manage lanes" },
  subCommands: { add, ls, edit, rm },
});
