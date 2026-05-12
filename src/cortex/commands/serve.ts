import { defineCommand } from "citty";
import fs from "node:fs";
import { Store } from "../store.ts";
import { startServer } from "../server.ts";
import { pidPath, urlPath, ensureConfigDir } from "../paths.ts";

export default defineCommand({
  meta: { name: "serve", description: "run the cortex API server (writes ~/.config/cortex/cortex.{pid,url})" },
  args: {
    port: {
      type: "string",
      alias: "p",
      default: "7777",
      valueHint: "port",
      description: "TCP port on 127.0.0.1 (0 = pick a free port)",
    },
    foreground: {
      type: "boolean",
      default: false,
      description: "run in the current shell instead of detaching as a daemon",
    },
  },
  run({ args }) {
    const port = Number.parseInt(args.port, 10);
    if (!Number.isFinite(port) || port < 0 || port > 65535) {
      console.error("error: --port must be a number 0-65535");
      process.exit(1);
    }

    if (!args.foreground) {
      ensureConfigDir();
      // In a `bun build --compile` binary, argv[1] is the embedded virtual
      // path (e.g. /$bunfs/root/cli.ts) which only resolves inside the parent
      // process. Drop it when re-spawning so the binary uses its own embedded
      // entrypoint. From source, argv[1] is the .ts script path which IS
      // re-runnable, so keep it.
      const reSpawnArgs = process.argv[1]?.startsWith("/$bunfs/")
        ? process.argv.slice(2)
        : process.argv.slice(1);
      const child = Bun.spawn(
        [process.execPath, ...reSpawnArgs, "--foreground"],
        {
          stdio: ["ignore", "ignore", "ignore"],
          detached: true,
        },
      );
      if (typeof child.unref === "function") child.unref();
      fs.writeFileSync(pidPath(), String(child.pid));
      const url = `http://127.0.0.1:${port}`;
      fs.writeFileSync(urlPath(), url);
      console.log(`✓ cortex serving at ${url} (pid ${child.pid})`);
      if (process.platform === "darwin") {
        try {
          Bun.spawn(["open", url]);
        } catch {
          /* best-effort */
        }
      }
      return;
    }

    const store = Store.open();
    const handle = startServer({ port, store });
    ensureConfigDir();
    fs.writeFileSync(pidPath(), String(process.pid));
    fs.writeFileSync(urlPath(), handle.url);
    console.log(`cortex listening on ${handle.url}`);

    const shutdown = async () => {
      try {
        await handle.stop();
      } catch {
        /* ignore */
      }
      store.close();
      try {
        fs.rmSync(pidPath(), { force: true });
        fs.rmSync(urlPath(), { force: true });
      } catch {
        /* ignore */
      }
      process.exit(0);
    };
    process.on("SIGTERM", shutdown);
    process.on("SIGINT", shutdown);
  },
});
