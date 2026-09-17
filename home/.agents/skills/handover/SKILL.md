---
name: handover
description: >-
  Two-way conversation handoff for pi. GIVING (/handover) summarizes the CURRENT conversation into a self-contained brief, copies it to the clipboard, and persists a durable, resumable cortex task whose body is that brief. RECEIVING (/pickup <task-id>) pulls a handover cortex task, consumes the brief, orients in the repo, and continues where the previous session left off. Use when the user runs /handover or /pickup, or asks to hand off, checkpoint, transfer, resume, or pick up a conversation. A deliberate step above generic /compact: self-contained (zero-context reader), preserves the verbatim request, includes a resume runbook, captures rejected paths + mental model + gotchas, recovers pre-compaction history from the session file, and is model-synthesized rather than mechanically truncated.
---

# Handover

Package the current conversation so a DIFFERENT agent, in a BRAND-NEW session
with zero shared memory, can continue the work without loss. Two deliverables:

1. A paste-ready handover brief on the system clipboard.
2. A durable, resumable cortex task whose body is the same brief.

This skill covers BOTH directions of a handoff:
- GIVING (`/handover`): create the brief + cortex task — the giving-side procedure below.
- RECEIVING (`/pickup <task-id>`): resume from a handover task — see "Receiving side" at the end of this file.

## Why this beats generic `/compact`

`/compact` frees context WITHIN a session: it summarizes old turns but keeps
the most recent ~20k tokens verbatim, so the SAME agent keeps going. A handover
has no kept tail — the receiving agent gets ONLY the brief. So this skill:

- Makes the brief fully SELF-CONTAINED (nothing assumed in the reader's head).
- Preserves the user's original request VERBATIM (compaction paraphrases).
- Adds a resume runbook (repo/branch/build/test/services) a cold agent needs.
- Captures the mental model, rejected alternatives, and gotchas discovered.
- RECOVERS history the live window already lost to auto-compaction, by mining
  the persistent session file (`PI_SESSION_FILE`) and any prior compaction /
  branch summaries stored in it.
- Attaches evidence to every "done" so completion is trustworthy.
- Persists a traceable, resumable cortex task, not just ephemeral text.

## Scripts & references (resolve against this skill's directory)

- `scripts/collect-context.sh` — read-only; gathers grounding FACTS.
- `scripts/clip.sh` — copies stdin to the clipboard, portably.
- `references/brief-template.md` — the exact brief structure to follow.

Invoke them by absolute path, e.g. `~/.agents/skills/handover/scripts/collect-context.sh`.

## Giving side (/handover): create the handoff

### Phase 1 — Ground (facts before synthesis)

Run the collector and read ALL of its output:

```bash
~/.agents/skills/handover/scripts/collect-context.sh
```

It surfaces: session metadata; git runbook facts (root, branch, status, log,
diff, gh-stack layer); cortex lane + existing tasks in it; the entry-type
histogram; any prior compaction/branch summaries; the VERBATIM original
request; every user message in order; files read; files modified; commands
run; model changes; and the last assistant message.

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

## Rules

- READ-ONLY except exactly TWO writes: the system clipboard and ONE cortex
  task. NEVER modify project files, run git write commands, stage, or commit.
- NEVER fabricate progress or evidence. Unverified claims MUST be labeled.
- SELF-CONTAINED: assume the receiving agent has nothing but the brief.
- Preserve the user's original request VERBATIM.
- Prefer the `cortex_update` tool for attribution (resumable) over `--as`.
- Keep the cortex title to one concise mission-level line.
- Degrade gracefully: no session file / no `jq` -> synthesize from memory;
  no `cortex` -> clipboard only, and say so; no clipboard tool -> report the
  saved file path from `clip.sh`.
- Honor the user's focus argument if provided.

## Return to the user (format)

**Handover complete.**
- **Cortex task:** #<id> — <title> (lane `<lane>`, tag `handover`)
- **Clipboard:** brief copied (<n> bytes) — paste into a new pi session to resume
- **Mission:** <one line>
- **Immediate next step:** <one line>
- **To resume:** start a fresh session and paste the clipboard, or hand task #<id> to an agent.

---

## Receiving side (/pickup): resume from a handover task

Goal: take a handover cortex task id, consume its brief, orient in the repo,
and continue the work — in a brand-new session with no prior context.

### Procedure

1. Require a task id (the `/pickup` argument). If none was given, list
   candidates and ask which to resume — do NOT guess:
   ```bash
   cortex ls -t handover            # optionally scope with: -l <lane>
   ```

2. Pull the task and read the brief. `.task.body` is the brief; `.updates` is
   its history:
   ```bash
   cortex show <id> --json | jq -r '.task.title, .task.status, (.task.tags|join(",")), "----", .task.body'
   ```
   If `.task.tags` does not include `handover`, WARN the user and continue only
   on their confirmation — the body may not be a handover brief.

3. Consume the brief in full. Prioritize: section 4 (Environment & Resume
   Runbook), 9 (Next Steps), 10 (Open Questions / Blockers / Risks), and 8
   (Rejected alternatives — do NOT re-explore those dead ends).

4. Orient in the environment (READ-ONLY): confirm you are in the repo root from
   section 4 (`cd` there if needed), then run the brief's "first orientation
   commands" — typically `git status`, `git branch --show-current`, `git diff`,
   and reading the key files listed in sections 5/7.

5. Reconcile brief vs reality. The repo may have changed since the brief was
   written (commits landed, branch switched, files moved). CURRENT REPO STATE
   WINS over the brief. Explicitly flag every material discrepancy to the user.

6. Restate the mission and the immediate next step in your own words, then
   CONFIRM the plan with the user before making any changes.

7. Link the resumption for resumability + audit trail — post an update via the
   `cortex_update` TOOL (this maps the NEW session to the task):
   ```
   cortex_update({ task_id: <id>, message: "resumed in a new session; continuing from Next Steps" })
   ```
   As work proceeds, post further updates; flip status to `done` when the
   mission is complete, or `blocked` with the reason if you get stuck.

8. Execute section 9 (Next Steps) in order, honoring the constraints in
   section 3 and the user's git protocol (NEVER commit unless asked).

### Rules (receiving side)

- Ground every claim in the task body + the live repo; NEVER invent state.
- When brief and repo disagree, TRUST the repo and surface the delta.
- Confirm before the first mutating action.
- Attribute via the `cortex_update` tool (resumable), not `cortex update --as`.
- Respect section 8 — do not re-explore rejected approaches.

### Return to the user (receiving side)

**Resumed from handover #<id>.**
- **Mission:** <one line from section 1>
- **Repo state vs brief:** <in sync / list discrepancies>
- **Immediate next step:** <the section-9 step you will do first>
- **Confirm?** <the one question you need answered before you start changing things>
