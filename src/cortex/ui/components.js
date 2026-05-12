// components.js — All Preact components for the cortex dashboard.
//
// Imports the data layer from ./state.js and presents it. Single file because
// the components are densely cross-referenced (e.g. ActiveTaskPane embeds
// EditTaskForm + PostUpdateForm + StatusPopover; CommandPalette references
// every action; ModalRoot dispatches to LaneEditModal). Splitting further
// would mean threading the same imports through 6+ files for no win.

import { h } from "https://esm.sh/preact@10.24";
import { useEffect, useRef } from "https://esm.sh/preact@10.24/hooks";
// useSignal returns a signal that's stable across re-renders. With plain
// signal() in render the value is replaced every keystroke and inputs freeze.
import { useSignal } from "https://esm.sh/@preact/signals@1.3?deps=preact@10.24";
import htm from "https://esm.sh/htm@3.1";
// highlight.js core + markdown grammar only. We do NOT compile/render the
// markdown — we show the raw source verbatim with token-level color so the
// user sees exactly what they typed (#, **, `, [text](url) etc. all visible)
// but with visual hierarchy. Core ~16KB, markdown lang ~5KB, loaded from
// esm.sh CDN at runtime so the binary stays the same size.
import hljs from "https://esm.sh/highlight.js@11.10/lib/core";
import markdownLang from "https://esm.sh/highlight.js@11.10/lib/languages/markdown";
hljs.registerLanguage("markdown", markdownLang);

// Auto-resize a textarea to fit its content. Attached as a ref callback so it
// works without re-rendering on every keystroke (which would fight htm). The
// __cortexAutoSized flag prevents double-binding on rerenders — the listener
// stays attached for the textarea's whole lifetime. min-height + viewport-
// capped max-height live in CSS (.autosize) so JS only computes the natural
// height.
const autosizeRef = (el) => {
  if (!el || el.__cortexAutoSized) return;
  el.__cortexAutoSized = true;
  const fit = () => {
    el.style.height = "auto";
    el.style.height = el.scrollHeight + "px";
  };
  el.addEventListener("input", fit);
  // Run once now (next paint) so initial content sizes correctly.
  requestAnimationFrame(fit);
};

import {
  // signals
  tasks, lanes, selectedLane, selectedId, editing, statusPopover, newLaneOpen,
  paletteOpen, modal, errorMsg, meAuthor,
  // computed
  tasksInLane, activeTask, inboxList,
  // api + error helpers
  api, showError, tryApi,
  // platform / hint helpers
  kbd,
  // pure helpers
  fmtTime, initial, STATUS, STATUS_LABEL, nextStatusFor, nextActionLabel,
  priorityClass, laneColor, LANE_COLORS,
  // navigation
  moveSelection,
  // theme
  theme, setTheme, toggleTheme,
} from "./state.js";

const html = htm.bind(h);

// Universal "save this form" keydown matcher. Used by every form (new task,
// new lane, edit task, lane edit modal, post update). Fires on Cmd/Ctrl+S
// and Cmd/Ctrl+Enter so muscle memory from any editor (⌘S in macOS, Ctrl+S
// in Win/Linux, ⌘⏎ / Ctrl+⏎ as the universal "submit" gesture) works.
// Returns a keydown handler you attach to the form (or to the focused input,
// for textareas where Enter alone has its own meaning).
const onSubmitKeys = (submit) => (e) => {
  if (e.isComposing) return; // skip mid-IME
  const meta = e.metaKey || e.ctrlKey;
  if (!meta) return;
  if (e.key === "Enter" || e.key === "s" || e.key === "S") {
    e.preventDefault();
    e.stopPropagation();
    submit();
  }
};

// ---------- icons (Lucide canonical: viewBox 24, fill none, stroke currentColor) ----------
const ICONS = {
  circle:        '<circle cx="12" cy="12" r="9"/>',
  eye:           '<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/>',
  ban:           '<circle cx="12" cy="12" r="9"/><line x1="5" y1="5" x2="19" y2="19"/>',
  checkCircle:   '<path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><polyline points="22 4 12 14.01 9 11.01"/>',
  star:          '<polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/>',
  pause:         '<rect x="6" y="4" width="4" height="16"/><rect x="14" y="4" width="4" height="16"/>',
  play:          '<polygon points="5 3 19 12 5 21 5 3"/>',
  plus:          '<line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/>',
  chevronDown:   '<polyline points="6 9 12 15 18 9"/>',
  moreHorizontal:'<circle cx="12" cy="12" r="1.5"/><circle cx="5" cy="12" r="1.5"/><circle cx="19" cy="12" r="1.5"/>',
  trash:         '<polyline points="3 6 5 6 21 6"/><path d="M19 6l-2 14a2 2 0 0 1-2 2H9a2 2 0 0 1-2-2L5 6"/><path d="M10 11v6M14 11v6"/><path d="M9 6V4a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2"/>',
  inbox:         '<polyline points="22 12 16 12 14 15 10 15 8 12 2 12"/><path d="M5.45 5.11L2 12v6a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-6l-3.45-6.89A2 2 0 0 0 16.76 4H7.24a2 2 0 0 0-1.79 1.11z"/>',
  sun:           '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41"/>',
  moon:          '<path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/>',
  monitor:       '<rect x="2" y="3" width="20" height="14" rx="2" ry="2"/><line x1="8" y1="21" x2="16" y2="21"/><line x1="12" y1="17" x2="12" y2="21"/>',
  keyboard:      '<rect x="2" y="6" width="20" height="12" rx="2"/><line x1="6" y1="10" x2="6" y2="10"/><line x1="10" y1="10" x2="10" y2="10"/><line x1="14" y1="10" x2="14" y2="10"/><line x1="18" y1="10" x2="18" y2="10"/><line x1="6" y1="14" x2="18" y2="14"/>',
  x:             '<line x1="6" y1="6" x2="18" y2="18"/><line x1="6" y1="18" x2="18" y2="6"/>',
};
function Icon({ name, size = 14, className = "" }) {
  const inner = ICONS[name] || "";
  return html`<svg class=${"icon " + className} width=${size} height=${size} viewBox="0 0 24 24"
    fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"
    dangerouslySetInnerHTML=${{ __html: inner }}></svg>`;
}

function PriorityChip({ priority }) {
  return html`<span class=${"priority-chip " + priorityClass(priority)}
    title=${`Priority ${priority} (0 = highest)`}>P${priority}</span>`;
}

// ---------- theme toggle ----------
// Two-state flip: light ↔ dark. Icon shows the DESTINATION (sun when in dark
// mode, moon when in light mode) so the affordance reads as "click to go
// there" — a convention shared by GitHub, VS Code, Notion, etc.
function ThemeToggle() {
  const isDark   = theme.value === "dark";
  const iconName = isDark ? "sun" : "moon";
  const next     = isDark ? "light" : "dark";
  return html`<button class="btn-icon" onClick=${toggleTheme}
    title=${`Switch to ${next} mode`}
    aria-label=${`Switch to ${next} mode`}>
    <${Icon} name=${iconName}/>
  </button>`;
}

// ---------- lanes pane ----------
function LanesPane() {
  // useSignal: stable across re-renders. With plain signal() the value reset
  // to "" on every keystroke (mutation -> re-render -> fresh signal) and
  // inputs felt frozen.
  const newLaneName = useSignal("");
  const newTaskTitle = useSignal("");
  // "All tasks" is a *view*, not a lane — it has no color, no editor, no
  // delete. Promote it to its own pane-section above "Lanes" so it doesn't
  // visually hijack a lane slot (where empty color/settings columns made it
  // look broken).
  const totalOpen = tasks.value.filter(t => t.status !== "done").length;
  return html`<aside class="pane pane-lanes">
    ${/* System controls strip — lives at the top of the left sidebar so app-
         level toggles (theme today, settings/profile later) sit above any
         domain content. Right-aligned bare icon buttons; no eyebrow label
         because position + treatment already convey "app chrome". */ ""}
    <div class="pane-system">
      <${ThemeToggle}/>
    </div>
    <div class="pane-section" style="padding-bottom: 8px">
      <button class=${"view-row" + (selectedLane.value === null ? " selected" : "")}
        onClick=${() => { selectedLane.value = null; selectedId.value = null; }}
        title="Show every task across all lanes">
        <${Icon} name="inbox"/>
        <span class="view-name">All tasks</span>
        <span class="view-count">${totalOpen}</span>
      </button>
    </div>
    ${/* Lanes and Tasks live in SEPARATE scroll surfaces — conceptually they
         answer different questions ("which lane am I in?" vs "which task in
         the current selection?") and merging their scroll context made it
         feel like the lane list was just a header for the task list.

         Lanes section: bounded to 50% of pane height when tasks list is
         also present (so a long lane list can't squeeze tasks out); takes
         all remaining middle space when tasks section is absent. Tasks
         section: takes the remaining vertical room and scrolls internally.
         All wired in CSS via :has() — see .lanes-section / .tasks-section. */ ""}
    <div class="pane-section lanes-section">
      ${/* .section-head is position:sticky inside the scroll container so the
           Lanes title + plus button stay visible as you scroll the lane
           list. The new-lane form (when open) lives in the head too so it
           anchors next to the trigger. */ ""}
      <div class="section-head">
        <div class="row">
          <h1 class="eyebrow grow">Lanes</h1>
          <button class="btn-icon" data-pop title="New lane"
            onClick=${e => { e.stopPropagation(); newLaneOpen.value = !newLaneOpen.value; }}>
            <${Icon} name="plus"/>
          </button>
        </div>
        ${newLaneOpen.value ? (() => {
          const submitNewLane = async () => {
            const n = newLaneName.value.trim(); if (!n) return;
            await tryApi(() => api.addLane({name: n})); newLaneName.value = ""; newLaneOpen.value = false;
          };
          return html`<form data-pop style="margin-top:8px"
            onSubmit=${e => { e.preventDefault(); submitNewLane(); }}
            onKeyDown=${onSubmitKeys(submitNewLane)}>
            <input autoFocus placeholder="lane name" style="width:100%; height:28px; padding:4px 8px"
              value=${newLaneName.value} onInput=${e => newLaneName.value = e.target.value}/>
          </form>`;
        })() : null}
      </div>
      <div class="section-body">
        ${lanes.value.map(l => {
          const open = tasks.value.filter(t => t.lane === l.name && t.status !== "done");
          const sel  = selectedLane.value === l.name;
          return html`<button
            class=${"lane-row" + (sel ? " selected" : "")}
            onClick=${() => { selectedLane.value = sel ? null : l.name; selectedId.value = null; }}
            onDragOver=${e => { e.preventDefault(); e.currentTarget.classList.add("dragover"); }}
            onDragLeave=${e => e.currentTarget.classList.remove("dragover")}
            onDrop=${async e => {
              e.currentTarget.classList.remove("dragover");
              const id = Number(e.dataTransfer.getData("application/x-cortex-task-id"));
              if (id) await tryApi(() => api.moveLane(id, l.name));
            }}
            title=${`${open.length} open task${open.length === 1 ? "" : "s"}`}>
            <span class="lane-color" style=${l.color ? `background: ${l.color}` : ""}></span>
            <span class="lane-name">${l.name}</span>
            <span class="lane-count num">${open.length}</span>
            <span class="lane-edit-btn" title="Edit lane"
              onClick=${e => { e.stopPropagation(); modal.value = { kind: "lane-edit", name: l.name }; }}>
              <${Icon} name="moreHorizontal" size=${12}/>
            </span>
          </button>`;
        })}
      </div>
    </div>
    ${tasks.value.length > 0 ? html`<div class="pane-section tasks-section">
      <div class="section-head">
        <h1 class="eyebrow">${selectedLane.value
          ? html`Tasks \u00b7 ${selectedLane.value}`
          : html`All tasks`}</h1>
      </div>
      <div class="section-body">
      ${tasksInLane.value.length === 0 ? html`<p class="meta">no tasks in this lane</p>` :
        tasksInLane.value.map(t => html`<button
          class=${"task-row" + (activeTask.value && t.id === activeTask.value.id ? " active" : "")}
          draggable="true"
          onDragStart=${e => e.dataTransfer.setData("application/x-cortex-task-id", String(t.id))}
          onClick=${() => selectedId.value = t.id}>
          <span class=${"dot dot-status-" + t.status}></span>
          <span class="task-title">${t.title}</span>
          <${PriorityChip} priority=${t.priority}/>
        </button>`)}
      </div>
    </div>` : null}
    <div class="pane-foot">
      ${(() => {
        const submitNewTask = async () => {
          const t = newTaskTitle.value.trim(); if (!t) return;
          const lane = selectedLane.value || "now";
          const created = await tryApi(() => api.addTask({ title: t, lane }));
          newTaskTitle.value = ""; if (created?.id) selectedId.value = created.id;
        };
        return html`<form onSubmit=${e => { e.preventDefault(); submitNewTask(); }}
          onKeyDown=${onSubmitKeys(submitNewTask)}>
          <div class="row">
            <input id="new-task-input" class="grow" placeholder="New task\u2026"
              value=${newTaskTitle.value} onInput=${e => newTaskTitle.value = e.target.value}
              style="height:32px"/>
            <button type="submit" class="btn btn-primary" style="height:32px" title="Add task">
              <${Icon} name="plus"/>
            </button>
          </div>
        </form>`;
      })()}
      <div class="row" style="margin-top:8px; justify-content:space-between">
        <button class="btn" style="height:24px; padding:0 8px"
          onClick=${() => paletteOpen.value = true}>
          <${Icon} name="keyboard" size=${12}/>
          <span>Commands</span>
          <span class="kbd">${kbd("P")}</span>
        </button>
      </div>
    </div>
  </aside>`;
}

// ---------- status popover ----------
function StatusPopover({ task }) {
  if (!statusPopover.value) return null;
  // Anchor to the right edge of the status pill so the menu extends LEFT.
  // The pill sits on the right side of the header (after the .grow spacer),
  // so left-anchoring would overflow into the inbox pane and trigger a
  // horizontal scroll on the main grid.
  return html`<div class="popover" data-pop style="top: 32px; right: 0">
    ${STATUS.map(s => html`<button class="popover-row" onClick=${async () => {
      statusPopover.value = false;
      await tryApi(() => api.setStat(task.id, s));
    }}>
      <span class=${"dot dot-status-" + s}></span>
      <span>${STATUS_LABEL[s]}</span>
      ${task.status === s ? html`<${Icon} name="checkCircle" size=${12}/>` : html`<span></span>`}
    </button>`)}
  </div>`;
}

// ---------- active task pane ----------
function ActiveTaskPane() {
  const at = activeTask.value;
  if (!at) return html`<section class="pane pane-active">
    <div class="empty">
      <${Icon} name="checkCircle" size=${32}/>
      <div class="empty-title">All caught up</div>
      <div class="empty-sub">Add a task in the lanes pane, or press <span class="kbd">${kbd("P")}</span> to open the command palette.</div>
    </div>
  </section>`;

  const next = nextStatusFor(at.status);
  const nextLabel = nextActionLabel(at.status);

  return html`<section class="pane pane-active">
    <header class="active-header">
      <span class="meta num">[${at.id}]</span>
      <span class="lane-chip">
        ${laneColor(at.lane) ? html`<span class="lane-color" style=${`background: ${laneColor(at.lane)}`}></span>` : null}
        <span>${at.lane}</span>
      </span>
      <${PriorityChip} priority=${at.priority}/>
      <span class="grow"></span>
      <div style="position:relative" data-pop>
        <button class="status-pill" data-pop
          onClick=${e => { e.stopPropagation(); statusPopover.value = !statusPopover.value; }}
          onDragOver=${e => { e.preventDefault(); e.currentTarget.classList.add("dragover"); }}
          onDragLeave=${e => e.currentTarget.classList.remove("dragover")}>
          <span class=${"dot dot-status-" + at.status}></span>
          <span>${STATUS_LABEL[at.status]}</span>
          <${Icon} name="chevronDown" size=${12}/>
        </button>
        <${StatusPopover} task=${at}/>
      </div>
    </header>

    <div class=${"active-body" + (editing.value ? " active-body--editing" : "")}>
      ${editing.value ? html`<${EditTaskForm} task=${at}/>` : html`<div class="stack">
        <h2 class="title-2"
          draggable="true"
          onDragStart=${e => e.dataTransfer.setData("application/x-cortex-task-id", String(at.id))}
          onClick=${() => editing.value = true}
          style="cursor:text"
          title="Click to edit">${at.title}</h2>
        ${/* Description display shows the raw markdown SOURCE with token-
             level syntax coloring — we deliberately do NOT render markdown.
             The user sees exactly what they typed (#, **, `, links, etc.) so
             editing round-trips losslessly. Click anywhere to enter edit mode. */ ""}
        <div class="md-display"
          onClick=${() => editing.value = true}
          style="cursor:text; min-height:96px"
          title="Click to edit (markdown source highlighting)">
          ${at.body
            ? html`<pre class="md-source"><code class="hljs"
                dangerouslySetInnerHTML=${{ __html: hljs.highlight(at.body, { language: "markdown" }).value }}/></pre>`
            : html`<p class="muted" style="margin:0">Add a description\u2026 (markdown syntax highlighted)</p>`}
        </div>
      </div>`}
    </div>

    <footer class="active-foot">
      <div class="row" style="margin-bottom:12px">
        <button class="btn btn-primary" onClick=${() => tryApi(() => api.setStat(at.id, next))}>
          <span>${nextLabel}</span>
        </button>
        <span class="grow"></span>
        <span class="meta">Updated ${fmtTime(at.updated)}</span>
        ${/* Dedicated delete button. Visible always (no hidden overflow menu)
             because deletion is a primary destructive action you should be
             able to discover at a glance. The confirm-delete modal still
             gates the actual destruction. */ ""}
        <button class="btn btn-icon btn-danger" title="Delete task"
          onClick=${() => modal.value = { kind: "confirm-delete", id: at.id }}>
          <${Icon} name="trash"/>
        </button>
      </div>
      <${PostUpdateForm} task=${at}/>
    </footer>
  </section>`;
}

function EditTaskForm({ task }) {
  // useSignal so typing actually accumulates instead of resetting per render.
  const t = useSignal(task.title);
  const b = useSignal(task.body || "");
  const p = useSignal(String(task.priority));
  const ln = useSignal(task.lane);
  const submit = async () => {
    await tryApi(async () => {
      await api.editTask(task.id, { title: t.value, body: b.value || null, priority: parseInt(p.value, 10) });
      if (ln.value !== task.lane) await api.moveLane(task.id, ln.value);
    });
    editing.value = false;
  };
  /* edit-task-form turns the form into a flex column whose .edit-body
    textarea owns the only scroll context in edit mode. The title input,
    priority/lane row, and cancel/save row stay at their natural height
    so they're always visible — the textarea takes the remaining space
    and scrolls internally when content exceeds it. NOT the autosize
    behaviour: in edit mode we deliberately want a bounded scroll surface
    so the form chrome is always reachable. */
  return html`<form class="edit-task-form"
    onSubmit=${e => { e.preventDefault(); submit(); }}
    onKeyDown=${onSubmitKeys(submit)}>
    <input value=${t.value} onInput=${e => t.value = e.target.value} placeholder="Task title"/>
    <textarea class="edit-body"
      placeholder="Description\u2026 (markdown syntax highlighted)"
      onInput=${e => b.value = e.target.value}>${b.value}</textarea>
    <div class="row">
      <label class="row meta" style="gap:6px">priority
        <input type="number" min="0" style="width:64px; height:28px" value=${p.value}
          onInput=${e => p.value = e.target.value}/>
      </label>
      <label class="row meta" style="gap:6px">lane
        <select style="height:28px" value=${ln.value} onChange=${e => ln.value = e.target.value}>
          ${lanes.value.map(l => html`<option value=${l.name}>${l.name}</option>`)}
        </select>
      </label>
      <span class="grow"></span>
      <button type="button" class="btn" onClick=${() => editing.value = false}>Cancel</button>
      <button type="submit" class="btn btn-primary">Save<span class="kbd">${kbd("S")}</span></button>
    </div>
  </form>`;
}

function PostUpdateForm({ task }) {
  const summary = useSignal("");
  // Default to the resolved "me" identity (gh username -> git -> hostname).
  // If meAuthor resolves AFTER mount and the user hasn't typed anything yet,
  // pick up the resolved value via the effect below.
  const author = useSignal(meAuthor.value);
  useEffect(() => {
    if (author.value === "me" || author.value === "") author.value = meAuthor.value;
  }, [meAuthor.value]);
  const len = summary.value.length;
  // Single submit path called from both onSubmit and the global Cmd/Ctrl+Enter
  // handler in app.js. We re-publish on every render so window.__cortexPostUpdate
  // always points at the current closure (with the current task + signal values).
  const submit = async () => {
    if (!summary.value.trim()) return;
    await tryApi(() => api.postUpd(task.id, { author: author.value, summary: summary.value }));
    summary.value = "";
  };
  window.__cortexPostUpdate = submit;
  return html`<form class="compose"
    onSubmit=${e => { e.preventDefault(); submit(); }}
    onKeyDown=${onSubmitKeys(submit)}>
    <textarea id="post-update-input" class="autosize" ref=${autosizeRef}
      placeholder="Post an update\u2026" rows="2"
      value=${summary.value}
      onInput=${e => summary.value = e.target.value}
      onKeyDown=${onSubmitKeys(submit)}/>
    <div class="compose-foot">
      <input class="author" title="Author (default from gh / git / hostname)"
        value=${author.value} onInput=${e => author.value = e.target.value}/>
      <span class="grow"></span>
      <span class=${"char-counter num" + (len > 180 ? " warn" : "")}>${len}/200</span>
      ${/* Hotkey hints live in the foot strip so they stay visible while the
           user is typing (placeholder hints disappear the moment text is
           entered — useless when discoverability matters most). */ ""}
      <span class="compose-hint meta" title="Focus this textarea from anywhere">
        <span class="kbd">${kbd("/")}</span> focus
      </span>
      <button type="submit" class="btn btn-primary" style="height:24px; padding:0 10px">
        <span>Post</span>
        <span class="kbd">${kbd("\u21b5")}</span>
      </button>
    </div>
  </form>`;
}

// ---------- inbox pane ----------
function InboxPane() {
  const at = activeTask.value;
  const list = inboxList.value;
  return html`<aside class="pane pane-inbox">
    <div class="inbox-header">
      <h1 class="eyebrow grow">Inbox</h1>
      ${at ? html`<span class="meta num">${list.length}</span>` : null}
    </div>
    ${list.length === 0 ? html`<div class="empty">
      <${Icon} name="inbox" size=${32}/>
      <div class="empty-title">No updates yet</div>
      <div class="empty-sub">${at ? "Post an update to start a thread." : "Select a task to see its updates."}</div>
    </div>` : list.map(u => html`<div class="inbox-row">
      <div class="row" style="gap:10px; align-items:flex-start">
        <span class="avatar">${initial(u.author)}</span>
        <div class="grow">
          <div class="summary">${u.summary}</div>
          <div class="meta">
            <span class=${"dot dot-status-" + (u.severity === "blocked" ? "blocked" : u.severity === "review" ? "review" : "open")}
              style="width:6px; height:6px"></span>
            <span>${u.author}</span>
            <span>\u00b7</span>
            <span>${fmtTime(u.created)}</span>
          </div>
        </div>
      </div>
    </div>`)}
  </aside>`;
}

// ---------- command palette ----------
function buildCommands() {
  const at = activeTask.value;
  const cmds = [];
  cmds.push({ id: "new-task",    label: "New task",              hint: "",       icon: "plus",        action: () => { paletteOpen.value = false; setTimeout(() => document.getElementById("new-task-input")?.focus(), 0); } });
  cmds.push({ id: "post-update", label: "Focus post-update box", hint: kbd("/"), icon: "eye",         action: () => { paletteOpen.value = false; setTimeout(() => document.getElementById("post-update-input")?.focus(), 0); } });
  cmds.push({ id: "next",        label: "Next task",             hint: "",       icon: "chevronDown", action: () => moveSelection(+1) });
  cmds.push({ id: "prev",        label: "Previous task",         hint: "",       icon: "chevronDown", action: () => moveSelection(-1) });
  if (at) {
    cmds.push({ id: "edit",   label: "Edit task\u2026", hint: `[${at.id}]`, icon: "eye", action: () => editing.value = true });
    for (const s of STATUS) {
      if (s !== at.status) cmds.push({ id: `status-${s}`, label: `Mark as ${STATUS_LABEL[s].toLowerCase()}`, hint: `[${at.id}]`, icon: "checkCircle", action: () => api.setStat(at.id, s) });
    }
    cmds.push({ id: "delete", label: "Delete task\u2026", hint: `[${at.id}]`, icon: "trash", action: () => modal.value = { kind: "confirm-delete", id: at.id } });
  }
  if (at) {
    for (const p of [0, 1, 2, 3, 5]) {
      if (p !== at.priority) {
        cmds.push({ id: `priority-${p}`, label: `Set priority P${p}` + (p === 0 ? " (urgent)" : ""), hint: `[${at.id}]`, icon: "star", action: () => api.editTask(at.id, { priority: p }) });
      }
    }
  }
  cmds.push({ id: "lane-all", label: "Show all lanes", hint: "", icon: "inbox", action: () => { selectedLane.value = null; selectedId.value = null; } });
  for (const l of lanes.value) {
    cmds.push({ id: `lane-${l.name}`,      label: `Filter to lane: ${l.name}`,  hint: "", icon: "inbox", action: () => { selectedLane.value = l.name; selectedId.value = null; } });
    cmds.push({ id: `lane-edit-${l.name}`, label: `Edit lane: ${l.name}\u2026`, hint: "", icon: "eye",   action: () => modal.value = { kind: "lane-edit", name: l.name } });
    if (l.name !== "now" && !tasks.value.some(t => t.lane === l.name)) {
      cmds.push({ id: `lane-del-${l.name}`, label: `Delete lane: ${l.name}\u2026`, hint: "", icon: "trash", action: () => modal.value = { kind: "confirm-lane-delete", name: l.name } });
    }
  }
  cmds.push({ id: "new-lane", label: "New lane\u2026", hint: "", icon: "plus", action: () => { newLaneOpen.value = true; setTimeout(() => document.querySelector(".pane-lanes input")?.focus(), 0); } });
  // Theme — a single command that flips to the other mode.
  cmds.push({
    id: "theme-toggle",
    label: theme.value === "dark" ? "Switch to light mode" : "Switch to dark mode",
    hint: "", icon: theme.value === "dark" ? "sun" : "moon",
    action: () => toggleTheme(),
  });
  return cmds;
}

// CommandPalette assumes it is conditionally rendered by the parent (so that
// each open is a true mount with fresh hook state). DO NOT add an
// `if (!paletteOpen.value) return null` early-return here — returning null
// from a component does NOT unmount it in Preact, the hook state persists,
// and useEffect(..., []) would fire only the very first time. That's the
// exact bug that broke autofocus on the second and subsequent opens.
function CommandPalette() {
  const query = useSignal("");
  const cursor = useSignal(0);
  const inputRef = useRef(null);
  // Autofocus the search box on every open. Because this component is now
  // truly remounted per open (see comment above), this useEffect fires every
  // time. We still defer once via setTimeout(..., 0) as a fallback for when
  // the keydown that opened the palette is still in flight and a stale focus
  // target would otherwise win.
  useEffect(() => {
    inputRef.current?.focus();
    const t = setTimeout(() => inputRef.current?.focus(), 0);
    return () => clearTimeout(t);
  }, []);
  // Keep the active row in view when ArrowDown/ArrowUp moves the cursor
  // past the visible viewport of .palette-list.
  useEffect(() => {
    const el = document.querySelector(".palette-list .palette-row.active");
    if (el && typeof el.scrollIntoView === "function") el.scrollIntoView({ block: "nearest" });
  });
  const cmds = buildCommands();
  const q = query.value.trim().toLowerCase();
  const filtered = q ? cmds.filter(c => c.label.toLowerCase().includes(q) || c.id.includes(q)) : cmds;
  const safeCursor = Math.min(cursor.value, Math.max(0, filtered.length - 1));
  const exec = async (cmd) => {
    paletteOpen.value = false;
    try { await cmd.action(); } catch (e) { showError(e); }
  };
  return html`<div class="overlay overlay-top" onClick=${e => { if (e.target.classList.contains("overlay") || e.target.classList.contains("overlay-top")) paletteOpen.value = false; }}>
    <div class="modal palette">
      <input ref=${inputRef} class="palette-input" placeholder="Type a command\u2026" autoFocus
        value=${query.value}
        onInput=${e => { query.value = e.target.value; cursor.value = 0; }}
        onKeyDown=${e => {
          if (e.key === "ArrowDown")    { e.preventDefault(); cursor.value = Math.min(filtered.length - 1, safeCursor + 1); }
          else if (e.key === "ArrowUp") { e.preventDefault(); cursor.value = Math.max(0, safeCursor - 1); }
          else if (e.key === "Enter")   { e.preventDefault(); const c = filtered[safeCursor]; if (c) exec(c); }
        }}/>
      <div class="palette-list">
        ${filtered.length === 0 ? html`<div class="meta" style="padding:12px">No matching commands</div>` :
          filtered.map((c, i) => html`<button class=${"palette-row" + (i === safeCursor ? " active" : "")}
            onMouseEnter=${() => cursor.value = i}
            onClick=${() => exec(c)}>
            <${Icon} name=${c.icon}/>
            <span class="grow">${c.label}</span>
            ${c.hint ? html`<span class="meta num">${c.hint}</span>` : null}
          </button>`)}
      </div>
      <div class="palette-foot meta">
        <span><span class="kbd">\u2191</span><span class="kbd">\u2193</span> navigate</span>
        <span><span class="kbd">\u21b5</span> select</span>
        <span><span class="kbd">Esc</span> close</span>
      </div>
    </div>
  </div>`;
}

// ---------- modals ----------
function ModalRoot() {
  const m = modal.value;
  if (!m) return null;
  const close = () => modal.value = null;
  if (m.kind === "confirm-delete") {
    return html`<div class="overlay" onClick=${e => { if (e.target.classList.contains("overlay")) close(); }}>
      <div class="modal">
        <h2>Delete task?</h2>
        <p class="meta" style="margin:0">This permanently removes the task and its updates. Cannot be undone.</p>
        <div class="modal-actions">
          <button class="btn" onClick=${close}>Cancel</button>
          <button class="btn btn-primary" style="background:var(--err)" onClick=${async () => {
            await tryApi(() => api.delTask(m.id)); selectedId.value = null; close();
          }}>Delete</button>
        </div>
      </div>
    </div>`;
  }
  if (m.kind === "lane-edit") {
    return html`<${LaneEditModal} name=${m.name} close=${close}/>`;
  }
  if (m.kind === "confirm-lane-delete") {
    return html`<div class="overlay" onClick=${e => { if (e.target.classList.contains("overlay")) close(); }}>
      <div class="modal">
        <h2>Delete lane <span class="meta">${m.name}</span>?</h2>
        <p class="meta" style="margin:0">The lane must be empty. The default <code>now</code> lane cannot be deleted.</p>
        <div class="modal-actions">
          <button class="btn" onClick=${close}>Cancel</button>
          <button class="btn btn-primary" style="background:var(--err)" onClick=${async () => {
            await tryApi(() => api.delLane(m.name));
            if (selectedLane.value === m.name) selectedLane.value = null;
            close();
          }}>Delete lane</button>
        </div>
      </div>
    </div>`;
  }
  return null;
}

function LaneEditModal({ name, close }) {
  const lane = lanes.value.find(l => l.name === name);
  if (!lane) { close(); return null; }
  const renameTo = useSignal(lane.name);
  const color    = useSignal(lane.color || null);
  const sort     = useSignal(String(lane.sort));
  const isDefault= lane.name === "now";
  const inUse    = tasks.value.some(t => t.lane === lane.name);
  const save = async () => {
    const fields = {};
    if (color.value !== (lane.color || null)) fields.color = color.value;
    const s = parseInt(sort.value, 10); if (Number.isFinite(s) && s !== lane.sort) fields.sort = s;
    if (renameTo.value && renameTo.value !== lane.name) fields.rename = renameTo.value.trim();
    if (Object.keys(fields).length === 0) { close(); return; }
    await tryApi(() => api.editLane(lane.name, fields));
    // If we renamed and this lane was selected, follow the rename.
    if (fields.rename && selectedLane.value === lane.name) selectedLane.value = fields.rename;
    close();
  };
  return html`<div class="overlay" onClick=${e => { if (e.target.classList.contains("overlay")) close(); }}>
    <div class="modal" style="max-width: 420px" onKeyDown=${onSubmitKeys(save)}>
      <div class="row">
        <h2 class="grow">Edit lane</h2>
        <button class="btn-icon" onClick=${close}><${Icon} name="x"/></button>
      </div>
      <label class="col" style="gap:4px">
        <span class="meta">Name</span>
        <input value=${renameTo.value} onInput=${e => renameTo.value = e.target.value}
          disabled=${isDefault} title=${isDefault ? "the 'now' lane cannot be renamed" : ""}/>
      </label>
      <div class="col" style="gap:4px">
        <span class="meta">Color</span>
        <div class="color-grid">
          ${LANE_COLORS.map(c => html`<button
            class=${"color-swatch" + (color.value === c ? " selected" : "") + (c === null ? " clear" : "")}
            style=${c ? `background: ${c}` : ""}
            title=${c || "no color"}
            onClick=${e => { e.preventDefault(); color.value = c; }}/>`)}
        </div>
      </div>
      <label class="col" style="gap:4px">
        <span class="meta">Sort order <span class="meta" style="opacity:0.7">(lower = higher in the list)</span></span>
        <input type="number" value=${sort.value} onInput=${e => sort.value = e.target.value}/>
      </label>
      <div class="row" style="justify-content:space-between">
        <button class="btn btn-danger"
          disabled=${isDefault || inUse}
          title=${isDefault ? "cannot delete 'now'" : inUse ? `${tasks.value.filter(t => t.lane === lane.name).length} task(s) in this lane` : "delete lane"}
          onClick=${() => modal.value = { kind: "confirm-lane-delete", name: lane.name }}>
          <${Icon} name="trash" size=${12}/>
          <span>Delete lane</span>
        </button>
        <div class="row">
          <button class="btn" onClick=${close}>Cancel</button>
          <button class="btn btn-primary" onClick=${save}>Save</button>
        </div>
      </div>
    </div>
  </div>`;
}

// ---------- root ----------
// Wraps the three panes + overlays in a transparent (display:contents) div so
// the panes are direct children of the <main> grid.
function App() {
  // CommandPalette is mounted ONLY when paletteOpen.value is true. The
  // ternary here is load-bearing: if we rendered it unconditionally and it
  // self-gated with `return null`, the component would never unmount and its
  // useEffect-based autofocus would only fire on the very first open. See
  // the comment above CommandPalette for the full failure mode.
  return html`<div class="contents">
    <${LanesPane}/>
    <${ActiveTaskPane}/>
    <${InboxPane}/>
    ${paletteOpen.value ? html`<${CommandPalette}/>` : null}
    <${ModalRoot}/>
    ${errorMsg.value ? html`<div class="toast">${errorMsg.value}</div>` : null}
  </div>`;
}

export default App;
