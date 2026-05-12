import { test, expect, beforeAll, afterAll, describe } from "bun:test";
import { Store } from "../store.ts";
import { startServer, type ServerHandle } from "../server.ts";

let store: Store;
let h: ServerHandle;

beforeAll(() => {
  store = Store.open(":memory:");
  h = startServer({ port: 0, store });
});

afterAll(async () => {
  await h.stop();
  store.close();
});

const j = async (path: string, init?: RequestInit) => {
  const r = await fetch(`${h.url}${path}`, init);
  const text = await r.text();
  return { status: r.status, body: text ? JSON.parse(text) : null, ct: r.headers.get("content-type") ?? "" };
};

describe("UI: served assets", () => {
  test("GET / returns the HTML shell linking the css + module entry", async () => {
    const r = await fetch(`${h.url}/`);
    const t = await r.text();
    expect(r.status).toBe(200);
    expect(r.headers.get("content-type") ?? "").toMatch(/text\/html/);
    expect(r.headers.get("cache-control") ?? "").toMatch(/no-store/);
    expect(t).toContain("<title>cortex</title>");
    expect(t).toContain('href="/styles.css"');
    expect(t).toContain('src="/app.js"');
    expect(t).toContain('type="module"');
  });

  test("GET /styles.css returns CSS with design tokens", async () => {
    const r = await fetch(`${h.url}/styles.css`);
    const t = await r.text();
    expect(r.status).toBe(200);
    expect(r.headers.get("content-type") ?? "").toMatch(/text\/css/);
    expect(r.headers.get("cache-control") ?? "").toMatch(/no-store/);
    // A few canonical tokens that should always be in the stylesheet.
    // (Accent value is theme-dependent and will drift; assert on the token
    // name itself, plus a structural class that should never go away.)
    expect(t).toMatch(/--accent:\s+#[0-9a-f]{6};/);
    expect(t).toContain(".pane-active");
    expect(t).toContain(".md-source");
    expect(t).toContain("--paper-dot");
  });

  test("GET /app.js returns the JS entry that imports App + state", async () => {
    const r = await fetch(`${h.url}/app.js`);
    const t = await r.text();
    expect(r.status).toBe(200);
    expect(r.headers.get("content-type") ?? "").toMatch(/javascript/);
    expect(r.headers.get("cache-control") ?? "").toMatch(/no-store/);
    expect(t).toContain('from "./components.js"');
    expect(t).toContain('from "./state.js"');
  });

  test("GET /components.js + /state.js return JS modules with pinned deps", async () => {
    const cs = await fetch(`${h.url}/components.js`);
    const ct = await cs.text();
    expect(cs.status).toBe(200);
    expect(ct).toContain("esm.sh/preact@10.24");
    expect(ct).toContain("esm.sh/htm@3.1");

    const st = await fetch(`${h.url}/state.js`);
    const stt = await st.text();
    expect(st.status).toBe(200);
    expect(stt).toContain("@preact/signals@1.3");
    expect(stt).toContain("export const tasks");
  });
});

describe("UI: /api/me identity endpoint", () => {
  test("returns an author string from the cascade (gh → git → hostname → 'me')", async () => {
    const r = await j("/api/me");
    expect(r.status).toBe(200);
    expect(typeof r.body.author).toBe("string");
    expect(r.body.author.length).toBeGreaterThan(0);
  });
});
