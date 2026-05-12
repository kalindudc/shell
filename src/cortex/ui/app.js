// app.js — Bootstrap entry point for the cortex dashboard.
//
// Wires DOM concerns to the data layer: mounts the Preact tree, subscribes to
// the daemon's SSE stream, fetches the resolved /api/me identity, and
// installs the two global event listeners (outside-click for popovers,
// keydown for global shortcuts). Imports App from components.js and the
// state/helpers it needs from state.js. No business logic lives here.

import { h, render } from "https://esm.sh/preact@10.24";
import htm from "https://esm.sh/htm@3.1";

import App from "./components.js";
import {
  refresh,
  meAuthor,
  closeAllPopovers,
  paletteOpen,
  modal,
  editing,
  statusPopover,
  newLaneOpen,
} from "./state.js";

const html = htm.bind(h);

// ---------- mount + initial data ----------
render(html`<${App}/>`, document.querySelector("main#app"));

// One-shot bootstrap of the default post-update author.
fetch("/api/me")
  .then(r => r.json())
  .then(d => { if (d?.author) meAuthor.value = d.author; })
  .catch(() => { /* fall back to "me" — non-fatal */ });

// Initial state load. The SSE handler below will keep us in sync after this.
refresh();

// ---------- SSE: server-side change notifications ----------
// Debounce because multiple events can fire in close succession (e.g. a
// task.added immediately followed by an update.posted). A single 50ms window
// collapses these into one refresh.
let pending = null;
const debounceRefresh = () => {
  if (pending) clearTimeout(pending);
  pending = setTimeout(() => { pending = null; refresh(); }, 50);
};
const ev = new EventSource("/events");
["task.added","task.updated","task.removed","update.posted","lane.changed"]
  .forEach(k => ev.addEventListener(k, debounceRefresh));

// ---------- outside-click closes any open popover ----------
// Elements that are *part of* a popover (or its trigger) carry data-pop, so a
// click on those is a no-op. Anything else closes everything.
document.addEventListener("click", (e) => {
  if (!e.target.closest || !e.target.closest("[data-pop]")) closeAllPopovers();
});

// ---------- global keyboard shortcuts ----------
// No single-key hotkeys (they hijack typing in inputs). Only meta-modified:
//   ⌘/Ctrl + P  or  ⌘/Ctrl + K   -> toggle command palette
//   ⌘/Ctrl + /                   -> jump cursor into the post-update textarea
//   ⌘/Ctrl + Enter               -> post the update (works while focused in textarea)
//   Esc                          -> close palette -> modal -> popover -> editing
window.addEventListener("keydown", (e) => {
  const meta = e.metaKey || e.ctrlKey;

  // Toggle palette.
  if (meta && (e.key === "p" || e.key === "k")) {
    e.preventDefault();
    paletteOpen.value = !paletteOpen.value;
    return;
  }

  // Focus post-update textarea from anywhere. Match BOTH e.key === "/" (US
  // layouts) and e.code === "Slash" (layout-independent) because non-US
  // keyboard layouts produce different glyphs for the slash key, but e.code
  // is always the physical key.
  if (meta && (e.key === "/" || e.code === "Slash")) {
    e.preventDefault();
    const ta = document.getElementById("post-update-input");
    if (ta) {
      ta.focus();
      ta.setSelectionRange?.(ta.value.length, ta.value.length);
    }
    return;
  }

  // Belt-and-suspenders for ⌘/Ctrl+Enter: catch globally if the textarea
  // handler missed it for any reason. window.__cortexPostUpdate is the
  // submit closure that PostUpdateForm publishes on every render.
  if (meta && e.key === "Enter") {
    const ta = document.getElementById("post-update-input");
    if (ta && document.activeElement === ta && typeof window.__cortexPostUpdate === "function") {
      e.preventDefault();
      window.__cortexPostUpdate();
      return;
    }
  }

  if (e.key === "Escape") {
    if (paletteOpen.value) { paletteOpen.value = false; return; }
    if (modal.value)       { modal.value = null;        return; }
    if (statusPopover.value || newLaneOpen.value) { closeAllPopovers(); return; }
    if (editing.value)     { editing.value = false;     return; }
  }
});
