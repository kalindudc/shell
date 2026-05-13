import { test, expect, describe, beforeAll, afterAll } from "bun:test";
import { Store, type Update } from "../store.ts";
import { startServer, type ServerHandle } from "../server.ts";
import { subscribe, type CortexEvent } from "../events.ts";

// bun:sqlite WAL serializes writes (one writer, many readers) and the
// `updates` table is append-only, so 8 parallel coding agents POSTing to
// the same task should ALL land — no row dropped, every author preserved,
// every event emitted exactly once.
//
// We subscribe to the in-process event bus directly (rather than chunked-
// reading the /events SSE stream) because:
//   1. The SSE handler installs its `subscribe()` call INSIDE the async
//      response handler — there's a race between fetch returning headers
//      and the subscription being live.
//   2. The bus *is* the source of truth for SSE; testing it directly is
//      strictly stricter than testing the wire-format derived from it.

let store: Store;
let h: ServerHandle;

beforeAll(() => {
  store = Store.open(":memory:");
  h = startServer({ port: 0, store });
  store.addTask({ title: "concurrent-target" });
});

afterAll(async () => {
  await h.stop();
  store.close();
});

describe("parallel-agent updates: 8 concurrent posts", () => {
  test("all 201, all rows persisted, all distinct authors, 8 update.posted events", async () => {
    // 1. Subscribe BEFORE firing POSTs so we never miss an event.
    const events: CortexEvent[] = [];
    const unsub = subscribe((ev) => {
      if (ev.kind === "update.posted") events.push(ev);
    });

    try {
      // 2. Fire 8 parallel POSTs with distinct author tags.
      const authors = Array.from({ length: 8 }, (_, i) => `agent-${i}`);
      const responses = await Promise.all(
        authors.map((author) =>
          fetch(`${h.url}/api/tasks/1/updates`, {
            method: "POST",
            headers: { "content-type": "application/json" },
            body: JSON.stringify({
              author,
              summary: `concurrent post from ${author}`,
            }),
          }),
        ),
      );

      // Every response is a 201.
      expect(responses.map((r) => r.status)).toEqual(Array(8).fill(201));

      // 3. Persistence — 8 rows, 8 distinct authors.
      const rows: Update[] = store.listUpdates(1);
      expect(rows.length).toBe(8);
      const seenAuthors = new Set(rows.map((u) => u.author));
      expect(seenAuthors.size).toBe(8);
      expect([...seenAuthors].sort()).toEqual([...authors].sort());

      // 4. Event bus — 8 update.posted events, one per POST.
      expect(events.length).toBe(8);
      const eventAuthors = new Set(
        events.map((e) => (e.payload as { author: string }).author),
      );
      expect(eventAuthors.size).toBe(8);
      expect([...eventAuthors].sort()).toEqual([...authors].sort());
    } finally {
      unsub();
    }
  });
});
