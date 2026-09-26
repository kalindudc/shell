---
name: handover
description: >-
  Conversation handoff for pi. GIVING (/handover [target] [focus]) hands off THIS
  conversation, or ANOTHER session when the first argument names one (session
  .jsonl path, cortex task id, pi-<uuid> tag, or session uuid). RECEIVING
  (/pickup <task-id>) resumes from a handover task. Inside Herdr (HERDR_ENV=1),
  GIVING also splits a pane below and auto-runs /pickup there.
---

# Handover

Package the current conversation so a DIFFERENT agent, in a BRAND-NEW session
with zero shared memory, can continue the work without loss. Two deliverables:

1. A paste-ready handover brief on the system clipboard.
2. A durable, resumable cortex task whose body is the same brief.
3. When this agent runs inside a Herdr pane (`HERDR_ENV=1`): a fresh pi in a
   new pane below this one that has already been sent `/pickup <id>` — see
   "Phase 4 — Herdr auto-pickup" below. Outside Herdr this is skipped.

This skill covers THREE directions of a handoff, through TWO commands:
- GIVING (`/handover [focus]`): create the brief + cortex task for THIS conversation — the giving-side procedure below.
- GIVING FOR ANOTHER SESSION (`/handover <target> [focus]` — same command; the FIRST argument names the session): create the brief + cortex task for a session you did NOT live through, from its persisted transcript. Full procedure: READ `references/giving-foreign.md` and follow it.
- RECEIVING (`/pickup <task-id>`): resume from a handover task. Full procedure: READ `references/receiving.md` and follow it.

Unlike `/compact` — which summarizes old turns but keeps ~20k recent tokens
verbatim in the SAME session — a handover carries nothing forward but the
brief, so the brief must be self-contained, verbatim on intent, evidence-backed,
and include a cold-start resume runbook.

### Deciding which session to hand off (do this before anything else)

Inspect the FIRST whitespace-separated argument of `/handover`:
- A session `.jsonl` path (anything containing `/` or ending in `.jsonl`), a cortex
  task id (`#370`, `370`, `task:370`), a `pi-<uuid>` attribution tag, or a session
  uuid / uuid prefix (>= 8 hex) → it is a TARGET: run `scripts/resolve-session.sh`
  on it, then READ `references/giving-foreign.md` and follow it. The rest of the
  arguments are focus text. Repair obvious paste damage (a stray space or
  line-wrap inside the path) and check the file exists before resolving.
- Anything else (or no argument) → hand off THIS conversation; all arguments are
  focus text. Use the flow below.
- If the resolver says `is_current: yes`, the target IS this conversation → use the
  normal `/handover` flow.
- Never redirect the user to another command; `/handover` is the only entry point.

## Scripts & references (resolve against this skill's directory)

- `scripts/collect-context.sh [--session <target> [--latest]] [--digest] [--out <file>]` —
  read-only; gathers grounding FACTS for the current session (no args) or for
  another session (`--session`). Always tees its report to a file (path on the
  first and last line) because pi's bash tool truncates long output.
- `scripts/resolve-session.sh [--latest] <target>` — read-only; turns a target
  (session `.jsonl` path | cortex task id | `pi-<uuid>` tag | uuid / prefix)
  into a session file + facts. Exit 0 resolved, 2 ambiguous (candidate table),
  1 not found. `collect-context.sh --session` calls it for you.
- `scripts/clip.sh` — copies stdin to the clipboard, portably.
- `scripts/herdr-pickup.sh <task-id> --cwd <repo-root> [--direction right|down] [--no-switch-focus] [--dry-run]` —
  Phase 4 helper and the ONLY place this skill drives Herdr. Inside a Herdr
  pane it splits, starts a fresh pi, sends `/pickup <task-id>`, verifies the
  resumed banner, and hands focus over; elsewhere it exits 3 (`status=skipped`).
  Requires `herdr`, `jq`, `cortex`. `--help` documents keys and exit codes.
- `references/brief-template.md` — the exact brief structure to follow.
- `references/giving-foreign.md` — the `/handover <target>` procedure (loaded only when handing off another session).
- `references/receiving.md` — the `/pickup` procedure (loaded only when resuming).

Invoke scripts by absolute path, e.g. `~/.agents/skills/handover/scripts/collect-context.sh`.

## Giving side (/handover): create the handoff for THIS conversation

### Phase 1 — Ground (facts before synthesis)

Run the collector and read ALL of its output:

```bash
~/.agents/skills/handover/scripts/collect-context.sh
```

It surfaces: session metadata; git runbook facts (root, branch, status, log,
diff, gh-stack layer); cortex lane + existing tasks in it; the active path
(abandoned `/tree` branches are dropped); the entry-type histogram; any prior
compaction/branch summaries; the VERBATIM original request; every user message
in order; files read; files modified; commands run; model changes; and the
last assistant message. The full report is also written to the `report_file`
named on its first line — `read` that if the bash tool truncated the output.

Reconcile these facts with your own in-context understanding. The facts are
authoritative for exact paths, commands, and the verbatim request — NEVER rely
on memory alone for those. The facts also recover anything auto-compaction
dropped from your live window; fold prior compaction/branch summaries in.

Degrade gracefully: if the session is ephemeral (no `PI_SESSION_FILE`) or `jq`
is missing, the collector says so — synthesize from your in-context memory and
continue. The rest of the flow is unchanged.

### Phase 2 — Synthesize the brief

Read `references/brief-template.md` and write the brief to follow it EXACTLY.

- Self-contained, dense, plain prose and tight lists. No filler.
- Preserve the original request VERBATIM in section 2.
- Attach EVIDENCE (quoted decisive output) to every completed item. NEVER
  claim something passed/works without proof; mark unverifiable items as such.
- Record decisions WITH rationale AND rejected alternatives / dead ends.
- Capture open questions, blockers, and any gotcha/footgun discovered.
- If the user passed focus instructions (the `/handover` argument), let them
  steer emphasis and ordering — but never drop the mandatory sections.
- The cortex task body is the brief sections 1-12 (NOT the bootstrap header —
  a task need not point at itself). Refer to it in section 12 as "this task".

Write the body to a tempfile:

```bash
BODY=$(mktemp -t handover.XXXXXX.md)
# write brief sections 1-12 into "$BODY"
```

### Phase 3 — Deliver (cortex task, then clipboard)

Create the cortex task FIRST so its real id can go into the clipboard copy's
bootstrap header. Follow the cortex persistence recipe.

1. Lane = repo root basename from the grounding facts, unless the user named
   one explicitly.

2. Create the task (title = one-line mission; `open` = ready to pick up):

   ```bash
   cortex add "<concise mission title>" --lane "<lane>" --status open --bodyFile "$BODY" -t handover
   # stdout: [<id>] <title>   -> capture <id>
   ```

   (The installed CLI advertises `--bodyFile`; `--body-file` is accepted as an
   alias too. `-s`/`--status` defaults to `open`.)

3. Attribute immediately via the `cortex_update` TOOL (resumable — NOT
   `cortex update --as`):

   ```
   cortex_update({ task_id: <id>, message: "handover brief created; ready to resume in a fresh session" })
   ```

   Optionally cross-link a related task the grounding surfaced by posting an
   update whose text contains `@<other-id>`.

4. Build the clipboard copy = bootstrap header (with the REAL id/lane/repo/
   branch/session filled in) + the brief body, and copy it:

   ```bash
   CLIP=$(mktemp -t handover-clip.XXXXXX.md)
   {
     # render the bootstrap header from references/brief-template.md with
     # #<id>, <lane>, <repo>, <branch>, <session_id> substituted, then:
     cat "$BODY"
   } > "$CLIP"
   ~/.agents/skills/handover/scripts/clip.sh < "$CLIP"
   ```

   If `clip.sh` reports no clipboard tool, tell the user the file path it
   preserved so they can copy it manually.

### Phase 4 — Herdr auto-pickup (only when this agent runs inside a Herdr pane)

Goal: the user never opens a terminal, starts pi, and types `/pickup` by hand.
When Herdr manages this pane, a fresh pi is started in a new pane below this
one (stacked) and sent `/pickup <id>`; it runs unattended until it asks the
user to confirm.

ALL Herdr mechanics live in ONE vetted script. Run it; do NOT improvise
`herdr` calls, and do NOT run bare `herdr` (it launches the TUI; nested
launches are blocked). Give the bash tool a timeout of at least 300 s — the
script waits for the new agent to finish orienting.

```bash
~/.agents/skills/handover/scripts/herdr-pickup.sh <id> --cwd "$ROOT"
```

`$ROOT` = the repo root from the brief's section 4. For another session it is
the TARGET's cwd when `cwd_state` says it exists on this machine, else `$PWD`
(and say so). Skip this phase, and say so, when Phase 3 degraded to
clipboard-only — without a cortex id there is nothing to pick up.

The script prints `key=value` lines and ends with `status=`. Read them; never
guess:

- exit 0 / `status=running` — pi runs in `pane_id=` as `agent=`.
  `banner=seen` means the receiving side printed `Resumed from handover #<id>`
  and focus was handed to it (`focus=switched`). `banner=not-seen` with
  `wait=timeout …` means it is still orienting; focus stays here. Report the
  values verbatim in the Herdr line of the return format.
- exit 3 / `status=skipped` — not inside Herdr or a prerequisite is missing
  (`reason=`). Mention it in one line only for `herdr-cli-missing`,
  `pi-kind-unsupported`, or `jq-missing`; otherwise stay silent. The manual
  "To resume" line applies.
- exit 1 / `status=failed` — a Herdr step failed (`step=`; the verbatim Herdr
  error and a read of the new pane are on stderr). Quote them, report
  `pane_id`/`agent` if printed so the user can look, and STOP. NEVER re-run
  the script or hand-roll the remaining steps: a stalled or timed-out prompt
  does not prove it was not delivered, and a second pi in the same pane is
  worse than none.
- exit 2 — usage error (bad id, missing `--cwd`). Fix the arguments once.

Options when the user asks for them: `--direction right` (side by side
instead of stacked), `--no-switch-focus` (stay in this pane), `--dry-run`
(print the exact commands, mutate nothing). The script performs exactly ONE split,
ONE `agent start`, ONE `agent prompt`; it never closes or moves panes and
never touches `herdr server`.

## Rules

- READ-ONLY except exactly TWO writes: the system clipboard and ONE cortex
  task (plus one cross-link update on the source task when handing off
  another session that came from / picked up a cortex task). Inside Herdr
  (`HERDR_ENV=1`) Phase 4 adds exactly ONE `pane split`, ONE `agent start`,
  and ONE `agent prompt`, all performed by `scripts/herdr-pickup.sh` in the
  pane it creates — never by hand-rolled `herdr` calls. NEVER modify project files, run git write commands, stage, or commit.
- NEVER fabricate progress or evidence. Unverified claims MUST be labeled.
- SELF-CONTAINED: assume the receiving agent has nothing but the brief.
- Preserve the user's original request VERBATIM.
- Prefer the `cortex_update` tool for attribution (resumable) over `--as`.
- Keep the cortex title to one concise mission-level line.
- Degrade gracefully: no session file / no `jq` -> synthesize from memory;
  no `cortex` -> clipboard only, and say so; no clipboard tool -> report the
  saved file path from `clip.sh`; not inside Herdr / no `herdr` CLI -> skip
  Phase 4 and keep the manual "To resume" line. EXCEPTION: when handing off ANOTHER session there is
  no memory to fall back on — without `jq` or the session file the resolver
  exits 1; STOP and tell the user instead of writing an ungrounded brief.
- Honor the user's focus argument if provided.

## Return to the user (format)

**Handover complete.**
- **Cortex task:** #<id> — <title> (lane `<lane>`, tag `handover`)
- **Clipboard:** brief copied (<n> bytes) — paste into a new pi session to resume
- **Herdr:** pickup running in pane `<pane-id>` as agent `pickup-<id>`, focus moved there | skipped — not inside Herdr | failed: <verbatim error>
- **Mission:** <one line>
- **Immediate next step:** <one line>
- **To resume (if the Herdr pickup did not run):** start a fresh session and paste the clipboard, or hand task #<id> to an agent.
