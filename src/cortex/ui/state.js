// state.js — Pure data layer for the cortex dashboard.
//
// Owns: signals, computed values, the API object, all pure helpers, and the
// reactive effects that mirror "active task" -> "loaded updates". Has no DOM
// side effects (no querySelector, no addEventListener, no render). Bootstrap
// (mounting, EventSource subscribe, /api/me fetch, window listeners) lives in
// app.js, which imports from here.
//
// Why a single state.js instead of finer-grained modules: the signals and
// helpers are densely cross-referenced, and splitting further would force
// every component import to grow without reducing real coupling.

import { signal, computed, effect } from "https://esm.sh/@preact/signals@1.3?deps=preact@10.24";

// ---------- signals ----------
export const tasks         = signal([]);
export const lanes         = signal([]);
export const updates       = signal({});
export const selectedLane  = signal(null);
export const selectedId    = signal(null);
export const editing       = signal(false);
export const statusPopover = signal(false);
export const newLaneOpen   = signal(false);
export const paletteOpen   = signal(false);
// modal kinds: 'confirm-delete' | 'lane-edit' | 'confirm-lane-delete'
export const modal         = signal(null);
export const errorMsg      = signal(null);
// Resolved on boot from /api/me (gh hosts.yml -> git user.name -> hostname -> "me").
export const meAuthor      = signal("me");
// Inbox tab: "updates" (default, shows the active task's update thread) or
// "authors" (shows recent author activity from /api/authors).
export const tab           = signal("updates");
// Author rollups loaded lazily when the Authors tab is opened. Each entry
// is { author, last_seen, posts } from /api/authors.
export const authors       = signal([]);

// ---------- platform-aware keyboard hint ----------
// macOS gets the ⌘ glyph; everyone else gets the literal word "Ctrl". Used by
// every keyboard hint in the UI so we never make a Linux user squint at a
// Mac key icon. Always include "+" between modifier and key for visual
// parity across platforms.
export const IS_MAC = typeof navigator !== "undefined"
  && /Mac|iPhone|iPad|iPod/.test(navigator.platform || navigator.userAgent || "");
export const MOD = IS_MAC ? "\u2318" : "Ctrl";
export const kbd = (key) => `${MOD} + ${key}`;

// ---------- theme ----------
// Two-state theme model: "light" or "dark". CSS handles both via
// :root[data-theme="light"|"dark"] selectors. JS is responsible for reading
// the persisted choice on boot, writing the dataset attribute, and
// persisting on toggle.
//
// First-load default: matchMedia(prefers-color-scheme: dark). After that,
// the user's choice always wins and is persisted forever — no "system"
// option that changes under them.
const THEME_KEY = "cortex-theme";
const THEME_VALUES = ["light", "dark"];

function systemPrefersDark() {
  if (typeof window === "undefined" || !window.matchMedia) return false;
  return window.matchMedia("(prefers-color-scheme: dark)").matches;
}

function readStoredTheme() {
  try {
    const v = localStorage.getItem(THEME_KEY);
    if (THEME_VALUES.includes(v)) return v;
  } catch { /* private mode — fall through */ }
  return systemPrefersDark() ? "dark" : "light";
}

export const theme = signal(readStoredTheme());

// Apply a theme to the DOM and persist it.
export function setTheme(mode) {
  if (!THEME_VALUES.includes(mode)) mode = "light";
  theme.value = mode;
  if (typeof document !== "undefined") {
    document.documentElement.setAttribute("data-theme", mode);
  }
  try { localStorage.setItem(THEME_KEY, mode); } catch { /* ignore */ }
}

// Flip light ↔ dark.
export function toggleTheme() {
  setTheme(theme.value === "dark" ? "light" : "dark");
}

// Apply the resolved theme to the DOM at module load (before first paint),
// so a hard refresh never flashes the wrong palette.
if (typeof document !== "undefined") setTheme(theme.value);

// ---------- computed ----------
export const tasksInLane = computed(() => {
  const lane = selectedLane.value;
  const all = tasks.value;
  return lane ? all.filter(t => t.lane === lane) : all;
});
export const activeTask = computed(() => {
  const list = tasksInLane.value;
  if (selectedId.value != null) {
    const t = list.find(x => x.id === selectedId.value);
    if (t) return t;
  }
  // Fall back to the highest-priority open task in the current view.
  return list.find(t => t.status !== "done") ?? list[0] ?? null;
});
export const inboxList = computed(() => {
  const at = activeTask.value;
  if (!at) return [];
  return [...(updates.value[at.id] ?? [])].reverse();
});
// Tasks currently in the blocked status. Drives the sticky red top-bar in
// App() and the click-to-jump behaviour (selects the first one).
export const blockedTasks = computed(() => tasks.value.filter(t => t.status === "blocked"));

// ---------- API ----------
const j = (p, init) => fetch(p, init).then(async r => {
  const txt = await r.text();
  const body = txt ? JSON.parse(txt) : null;
  if (!r.ok) throw new Error(body?.error ?? r.statusText);
  return body;
});
export const api = {
  tasks:    ()                => j("/api/tasks"),
  lanes:    ()                => j("/api/lanes"),
  updates:  (id)              => j(`/api/tasks/${id}/updates`),
  addTask:  (b)               => j("/api/tasks",            { method:"POST",   headers:{"content-type":"application/json"}, body: JSON.stringify(b) }),
  editTask: (id, b)           => j(`/api/tasks/${id}`,      { method:"PATCH",  headers:{"content-type":"application/json"}, body: JSON.stringify(b) }),
  setStat:  (id, status)      => j(`/api/tasks/${id}/status`,{ method:"PATCH", headers:{"content-type":"application/json"}, body: JSON.stringify({status}) }),
  moveLane: (id, lane)        => j(`/api/tasks/${id}/lane`, { method:"PATCH",  headers:{"content-type":"application/json"}, body: JSON.stringify({lane}) }),
  delTask:  (id)              => j(`/api/tasks/${id}`,      { method:"DELETE" }),
  postUpd:  (id, b)           => j(`/api/tasks/${id}/updates`, { method:"POST", headers:{"content-type":"application/json"}, body: JSON.stringify(b) }),
  addLane:  (b)               => j("/api/lanes",            { method:"POST",   headers:{"content-type":"application/json"}, body: JSON.stringify(b) }),
  editLane: (n, b)            => j(`/api/lanes/${encodeURIComponent(n)}`, { method:"PATCH",  headers:{"content-type":"application/json"}, body: JSON.stringify(b) }),
  delLane:  (n)               => j(`/api/lanes/${encodeURIComponent(n)}`, { method:"DELETE" }),
};

// ---------- error surfacing ----------
export const showError = (e) => {
  const msg = String(e?.message ?? e);
  errorMsg.value = msg;
  // Clear the toast after 4s — but only if it's still the same message we set.
  // Otherwise a newer error would flash and immediately disappear.
  setTimeout(() => { if (errorMsg.value === msg) errorMsg.value = null; }, 4000);
};
export const tryApi = async (fn) => {
  try { return await fn(); } catch (e) { showError(e); throw e; }
};

// Lazy load of the author rollup. Called when the user opens the Authors
// tab in the inbox pane. Errors surface via the standard toast.
export const fetchAuthors = async () => {
  try {
    authors.value = await fetch("/api/authors").then(r => r.json());
  } catch (e) {
    showError(e);
  }
};

// ---------- refresh ----------
// Re-pulls tasks + lanes (and updates for the active task) from the server.
// Called at boot and on every SSE event from the daemon (debounced in app.js).
export async function refresh() {
  try {
    const [ts, ls] = await Promise.all([api.tasks(), api.lanes()]);
    tasks.value = ts; lanes.value = ls;
    const at = activeTask.value;
    if (at) updates.value = { ...updates.value, [at.id]: await api.updates(at.id) };
  } catch (err) {
    showError(err);
  }
}

// Reactive: when activeTask changes id, lazily fetch its updates so the inbox
// pane is populated even if the task was created mid-session.
let lastActive = null;
effect(() => {
  const at = activeTask.value;
  if (at && at.id !== lastActive) {
    lastActive = at.id;
    api.updates(at.id)
      .then(u => { updates.value = { ...updates.value, [at.id]: u }; })
      .catch(() => { /* swallow — listing is non-critical */ });
  }
});

// ---------- pure helpers ----------
export const fmtTime = (ms) => {
  const s = Math.floor((Date.now() - ms) / 1000);
  if (s < 60) return s + "s ago";
  if (s < 3600) return Math.floor(s/60) + "m ago";
  if (s < 86400) return Math.floor(s/3600) + "h ago";
  return Math.floor(s/86400) + "d ago";
};
export const initial = (s) => (s || "?").trim().charAt(0).toUpperCase();
export const STATUS = ["open","review","blocked","done"];
export const STATUS_LABEL = { open: "Open", review: "In review", blocked: "Blocked", done: "Done" };
export const nextStatusFor   = (s) => ({ open: "review", review: "done", blocked: "open", done: "open" }[s]);
export const nextActionLabel = (s) => ({ open: "Move to review", review: "Mark done", blocked: "Unblock", done: "Reopen" }[s]);

// Priority: 0 = highest. Render as P0/P1/... with urgent/high/normal styling.
export const priorityClass = (p) => p === 0 ? "urgent" : p === 1 ? "high" : "";

// Lookup a lane's color (or null). Used by lane chip + color dot in lists.
export const laneColor = (name) => lanes.value.find(l => l.name === name)?.color || null;

// Curated swatch palette for the lane color picker. null = "no color".
export const LANE_COLORS = [
  null,
  "#fe8019",
  "#dc2626","#d97706","#16a34a","#2563eb","#7c3aed","#db2777",
  "#f87171","#fbbf24","#4ade80","#60a5fa","#a78bfa","#f472b6",
  "#94a3b8","#475569",
];

// ---------- selection navigation ----------
// Cycle the active selection forwards/backwards through tasksInLane. Used by
// the command palette's "Next task"/"Previous task" entries.
export function moveSelection(delta) {
  const list = tasksInLane.value;
  if (list.length === 0) return;
  const at = activeTask.value;
  const i = Math.max(0, list.findIndex(t => at && t.id === at.id));
  const next = list[(i + delta + list.length) % list.length];
  selectedId.value = next.id;
}

// ---------- popover bookkeeping ----------
// Centralised so the outside-click listener (app.js) and Esc handler (app.js)
// don't have to know which popover signals exist.
export function closeAllPopovers() {
  statusPopover.value = false;
  newLaneOpen.value = false;
}
