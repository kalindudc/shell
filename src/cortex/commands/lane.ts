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
      description: "display color hex (e.g. #fe8019); used by the dashboard in Plan 2",
    },
    wip: {
      type: "string",
      alias: "w",
      valueHint: "int",
      description: "work-in-progress soft limit (default: 3)",
    },
  },
  async run({ args }) {
    const wip = args.wip ? Number.parseInt(args.wip, 10) : undefined;
    if (args.wip && (!Number.isFinite(wip) || (wip as number) < 0)) {
      console.error("error: --wip must be a non-negative integer");
      process.exit(1);
    }
    const payload = {
      name: args.name,
      color: args.color || null,
      wip_limit: wip,
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
          wip_limit: l.wip_limit,
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
    wip: {
      type: "string",
      alias: "w",
      valueHint: "int",
      description: "new WIP limit (non-negative integer)",
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
      wip_limit?: number;
      rename?: string;
    } = {};
    if (args.color) fields.color = args.color;
    if (args.wip) {
      const n = Number.parseInt(args.wip, 10);
      if (!Number.isFinite(n) || n < 0) {
        console.error("error: --wip must be a non-negative integer");
        process.exit(1);
      }
      fields.wip_limit = n;
    }
    if (args.rename) fields.rename = args.rename;
    if (Object.keys(fields).length === 0) {
      console.error("error: provide at least one of --color, --wip, --rename");
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
