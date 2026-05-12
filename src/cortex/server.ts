import { Hono } from "hono";
import { streamSSE } from "hono/streaming";
import { Store, type TaskStatus } from "./store.ts";
import { emit, subscribe, type CortexEvent } from "./events.ts";
import pkg from "./package.json" with { type: "json" };

const VERSION = pkg.version;
const isStatus = (v: string): v is TaskStatus =>
  v === "open" || v === "review" || v === "blocked" || v === "done";

export function buildApp(store: Store): Hono {
  const app = new Hono();

  app.get("/", (c) =>
    c.text("cortex API running\nPlan 2 ships the UI.\n"),
  );

  app.get("/api/health", (c) => c.json({ ok: true, version: VERSION }));

  // ---------- tasks ----------
  app.get("/api/tasks", (c) => {
    const lane = c.req.query("lane");
    const statusQ = c.req.query("status");
    const status = statusQ && isStatus(statusQ) ? statusQ : undefined;
    return c.json(store.listTasks({ lane, status }));
  });

  app.post("/api/tasks", async (c) => {
    const body = (await c.req.json().catch(() => ({}))) as {
      title?: string;
      lane?: string;
      body?: string | null;
      priority?: number;
      status?: TaskStatus;
    };
    if (!body.title || typeof body.title !== "string") {
      return c.json({ error: "title is required" }, 400);
    }
    const task = store.addTask(body as { title: string });
    emit({ kind: "task.added", payload: task, ts: Date.now() });
    return c.json(task, 201);
  });

  app.get("/api/tasks/:id", (c) => {
    const id = Number(c.req.param("id"));
    const task = store.getTask(id);
    if (!task) return c.json({ error: "not found" }, 404);
    return c.json(task);
  });

  app.patch("/api/tasks/:id", async (c) => {
    const id = Number(c.req.param("id"));
    const fields = (await c.req.json().catch(() => ({}))) as {
      title?: string;
      body?: string | null;
      priority?: number;
    };
    try {
      const task = store.editTask(id, fields);
      emit({ kind: "task.updated", payload: task, ts: Date.now() });
      return c.json(task);
    } catch (err) {
      return c.json({ error: (err as Error).message }, 404);
    }
  });

  app.patch("/api/tasks/:id/status", async (c) => {
    const id = Number(c.req.param("id"));
    const body = (await c.req.json().catch(() => ({}))) as { status?: string };
    if (!body.status || !isStatus(body.status)) {
      return c.json({ error: "invalid status" }, 400);
    }
    try {
      const task = store.setStatus(id, body.status);
      emit({ kind: "task.updated", payload: task, ts: Date.now() });
      return c.json(task);
    } catch (err) {
      return c.json({ error: (err as Error).message }, 404);
    }
  });

  app.patch("/api/tasks/:id/lane", async (c) => {
    const id = Number(c.req.param("id"));
    const body = (await c.req.json().catch(() => ({}))) as { lane?: string };
    if (!body.lane || typeof body.lane !== "string") {
      return c.json({ error: "lane is required" }, 400);
    }
    try {
      const task = store.moveTask(id, body.lane);
      emit({ kind: "task.updated", payload: task, ts: Date.now() });
      return c.json(task);
    } catch (err) {
      return c.json({ error: (err as Error).message }, 400);
    }
  });

  app.delete("/api/tasks/:id", (c) => {
    const id = Number(c.req.param("id"));
    try {
      store.removeTask(id);
      emit({ kind: "task.removed", payload: { id }, ts: Date.now() });
      return c.json({ ok: true });
    } catch (err) {
      return c.json({ error: (err as Error).message }, 404);
    }
  });

  // ---------- updates ----------
  app.get("/api/tasks/:id/updates", (c) => {
    const id = Number(c.req.param("id"));
    return c.json(store.listUpdates(id));
  });

  app.post("/api/tasks/:id/updates", async (c) => {
    const id = Number(c.req.param("id"));
    const body = (await c.req.json().catch(() => ({}))) as {
      author?: string;
      summary?: string;
      body?: string | null;
    };
    if (!body.summary || !body.author) {
      return c.json({ error: "author and summary are required" }, 400);
    }
    try {
      const update = store.addUpdate({
        task_id: id,
        author: body.author,
        summary: body.summary,
        body: body.body,
      });
      emit({ kind: "update.posted", payload: update, ts: Date.now() });
      return c.json(update, 201);
    } catch (err) {
      return c.json({ error: (err as Error).message }, 400);
    }
  });

  // ---------- lanes ----------
  app.get("/api/lanes", (c) => c.json(store.listLanes()));

  app.post("/api/lanes", async (c) => {
    const body = (await c.req.json().catch(() => ({}))) as {
      name?: string;
      color?: string | null;
      wip_limit?: number;
      sort?: number;
    };
    if (!body.name || typeof body.name !== "string") {
      return c.json({ error: "name is required" }, 400);
    }
    try {
      const lane = store.addLane(body as { name: string });
      emit({ kind: "lane.changed", payload: lane, ts: Date.now() });
      return c.json(lane, 201);
    } catch (err) {
      return c.json({ error: (err as Error).message }, 400);
    }
  });

  app.patch("/api/lanes/:name", async (c) => {
    const name = c.req.param("name");
    const fields = (await c.req.json().catch(() => ({}))) as {
      color?: string | null;
      wip_limit?: number;
      sort?: number;
      rename?: string;
    };
    try {
      const lane = store.editLane(name, fields);
      emit({ kind: "lane.changed", payload: lane, ts: Date.now() });
      return c.json(lane);
    } catch (err) {
      return c.json({ error: (err as Error).message }, 404);
    }
  });

  app.delete("/api/lanes/:name", (c) => {
    const name = c.req.param("name");
    try {
      store.removeLane(name);
      emit({ kind: "lane.changed", payload: { removed: name }, ts: Date.now() });
      return c.json({ ok: true });
    } catch (err) {
      return c.json({ error: (err as Error).message }, 400);
    }
  });

  // ---------- SSE ----------
  app.get("/events", (c) =>
    streamSSE(c, async (stream) => {
      const unsub = subscribe((ev: CortexEvent) => {
        void stream.writeSSE({
          event: ev.kind,
          data: JSON.stringify(ev.payload),
          id: String(ev.ts),
        });
      });
      stream.onAbort(() => unsub());
      while (!stream.aborted) {
        await stream.sleep(15000);
        if (stream.aborted) break;
        await stream.writeSSE({ event: "heartbeat", data: String(Date.now()) });
      }
    }),
  );

  return app;
}

export type ServerHandle = {
  port: number;
  url: string;
  stop(): Promise<void>;
};

export function startServer({
  port,
  store,
}: {
  port: number;
  store: Store;
}): ServerHandle {
  const app = buildApp(store);
  const server = Bun.serve({
    port,
    hostname: "127.0.0.1",
    fetch: app.fetch,
  });
  return {
    port: server.port,
    url: `http://127.0.0.1:${server.port}`,
    async stop() {
      server.stop(true);
    },
  };
}
