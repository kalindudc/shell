---
name: handover
description: >-
  Conversation handoff for pi. GIVING (/handover [target] [focus]) hands off THIS
  conversation, or ANOTHER session when the first argument names one (session
  .jsonl path, cortex task id, pi-<uuid> tag, or session uuid). RECEIVING
  (/pickup <task-id>) resumes from a handover task.
---

# Handover

Package the current conversation so a DIFFERENT agent, in a BRAND-NEW session
with zero shared memory, can continue the work without loss. Two deliverables:

1. A paste-ready handover brief on the system clipboard.
2. A durable, resumable cortex task whose body is the same brief.

This skill covers THREE directions of a handoff, through TWO commands:
- GIVING (`/handover [focus]`): create the brief + cortex task for THIS conversation — the giving-side procedure below.
- GIVING FOR ANOTHER SESSION (`/handover <target> [focus]` — same command; the FIRST argument names the session): create the brief + cortex task for a session you did NOT live through, from its persisted transcript — see "Giving for another session". There is no separate `/handover-for` command.
- RECEIVING (`/pickup <task-id>`): resume from a handover task — see "Receiving side" at the end of this file.

### Deciding which session to hand off (do this before anything else)

Inspect the FIRST whitespace-separated argument of `/handover`:
- A session `.jsonl` path (anything containing `/` or ending in `.jsonl`), a cortex
  task id (`#370`, `370`, `task:370`), a `pi-<uuid>` attribution tag, or a session
  uuid / uuid prefix (>= 8 hex) → it is a TARGET: run `scripts/resolve-session.sh`
  on it and follow "Giving for another session". The rest of the arguments are
  focus text. Repair obvious paste damage (a stray space or line-wrap inside the
  path) and check the file exists before resolving.
- Anything else (or no argument) → hand off THIS conversation; all arguments are
  focus text.
- If the resolver says `is_current: yes`, the target IS this conversation → use the
  normal `/handover` flow.
- Never redirect the user to another command; `/handover` is the only entry point.

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

- `scripts/collect-context.sh [--session <target> [--latest]] [--digest] [--out <file>]` —
  read-only; gathers grounding FACTS for the current session (no args) or for
  another session (`--session`). Always tees its report to a file (path on the
  first and last line) because pi's bash tool truncates long output.
- `scripts/resolve-session.sh [--latest] <target>` — read-only; turns a target
  (session `.jsonl` path | cortex task id | `pi-<uuid>` tag | uuid / prefix)
  into a session file + facts. Exit 0 resolved, 2 ambiguous (candidate table),
  1 not found. `collect-context.sh --session` calls it for you.
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

---

## Giving for another session (/handover <target> [focus])

Goal: produce the same two deliverables (clipboard brief + cortex task) for a
session you did NOT participate in — a minion's run, a colleague's session on
this machine, an earlier session that was never handed off, or the session(s)
that posted updates on a cortex task. You have ZERO memory of that
conversation: its persisted transcript is the only source of truth.

### Target grammar (the first `/handover` argument)

| Form | Example | Resolves via |
|---|---|---|
| Session file path | `~/.pi/agent/sessions/--…--/2026-…_01a0….jsonl`, `./run.jsonl` | the file itself (anything containing `/` or ending in `.jsonl`) |
| Cortex task id | `#370`, `370`, `task:370` | `cortex show <id> --json` → `pi-<uuid>` authors in `.updates[]` (the same set `cortex resume` offers) |
| Cortex attribution tag | `pi-01a0b072-b86f-7057-a92b-c086ef0bf98d` | the uuid after `pi-` → `*_<uuid>.jsonl` under the session root |
| pi session id / prefix | `01a0b072-b86f-…`, `01a0b072` (>= 8 hex) | same lookup; prefix semantics match `pi --session <partial-id>` |

Everything after the target is focus text, exactly like `/handover [focus]`.
Session root = `--session-dir`, else `$PI_CODING_AGENT_SESSION_DIR`, else
`~/.pi/agent/sessions` (searched recursively — minion sessions live under a
`minions/` subdirectory). The header `id` inside the file is always verified.

### Phase 0 — Resolve the target (never guess)

```bash
~/.agents/skills/handover/scripts/resolve-session.sh <target>
```

- exit 0 → facts printed (`session_file`, `session_id`, `session_cwd`,
  `cwd_state`, `created`, `last_activity`, `entries`, `size`, `session_name`,
  `is_current`). Continue.
- exit 2 → AMBIGUOUS. A cortex task with several `pi-` sessions prints a
  numbered table (author, update count, last update, last summary, on disk);
  a short uuid prefix prints the matching ids. Show the table to the user and
  ASK which session to hand over — unless the user already said "latest" /
  "most recent", in which case re-run with `--latest`. Then continue with the
  chosen `pi-<uuid>` as the target.
- exit 1 → not found / unusable (no `pi-` authors on the task, session file
  only exists on another machine, malformed target). STOP and report the exact
  error; suggest `cortex show <id>` or `pi -r` to locate the right session.
- `is_current: yes` → the target IS this session; fall back to the normal
  `/handover` flow.

### Phase 1 — Ground (the transcript IS your memory)

```bash
~/.agents/skills/handover/scripts/collect-context.sh --session <resolved target> [--latest]
```

Read the ENTIRE report. It is tee'd to `report_file` (first line); if the bash
tool says the output was truncated, `read` that file — in chunks if large —
rather than re-running. In FOREIGN mode the report adds, on top of the normal
sections:

- `mode: FOREIGN` banner, generating vs target session identities, provider/
  model taken from the transcript, and a `liveness` line (a file modified in
  the last 10 minutes may belong to a RUNNING session).
- Git facts computed in the TARGET session's `cwd` (`git -C`), labelled as the
  CURRENT state of that repo — it may have moved since `last_activity`. If the
  cwd is missing on this machine the report says so; the brief must too.
- Cortex lane derived from the TARGET cwd, and — when the target came from a
  cortex task — that task's title/status/tags and its last 12 updates.
- ACTIVE PATH: abandoned `/tree` branches are dropped (pi's leaf on reload is
  the last entry; the collector walks `parentId` to the root). The filtered
  transcript is saved as `active_path_file` next to the report.
- TRANSCRIPT DIGEST: the whole active path in order — user + assistant text,
  tool calls as `→ tool {args}` one-liners, bash results, tool errors,
  compactions, model changes — with per-entry caps (`HANDOVER_DIGEST_LEVEL=full`
  lifts them). This is your only memory of the session: read ALL of it.
- DRILL-DOWN CHEAT SHEET: `jq` one-liners against the raw file for fetching a
  tool result by `toolCallId`, an entry by id, or grepping — use them to pull
  exact evidence the digest truncated.

You MAY inspect the target repo READ-ONLY to reconcile (`git -C <cwd> status`,
`log`, `diff`, reading files the session touched). Do NOT run its builds,
tests, or services — you are documenting that session's evidence, not
producing new evidence in a repo you were not asked to work in.

### Phase 2 — Synthesize (same template, different provenance)

Follow `references/brief-template.md` exactly, with these differences:

- Section 2's verbatim request is the TARGET session's first user message
  (from the ORIGINAL REQUEST section), not anything said in this conversation.
- Evidence comes from the digest / raw transcript (quote tool results, test
  output, error lines). Where the transcript shows a claim without proof,
  write "claimed in transcript, unverified". NEVER fill gaps from this
  conversation or from general knowledge about the repo.
- Section 4 states the repo facts are as of generation time and flags any
  drift between `last_activity` and the current `head_date`/status.
- Section 1 or 10 says if the session looked live (`liveness`), so the reader
  knows the tail may be in flight and the origin agent may still be working.
- Section 12 uses the PROVENANCE variant for generated-on-behalf-of briefs:
  origin session = target id/file, generated by = `PI_SESSION_ID` (this
  session), source = the target as given (`task:370 → pi-…`), snapshot as of
  `last_activity`.
- If the target was resolved from a cortex task, list its OTHER `pi-` sessions
  (from the resolver table) in section 11 as related sessions — the handover
  covers only the one you resolved.

### Phase 3 — Deliver (same recipe, different lane and links)

- Lane = repo basename of the TARGET session's cwd (`suggested_lane` in the
  report), unless the user named one.
- Title prefix the mission with the origin so it is findable, e.g.
  `Handover (from session 01a0b072): <mission>`.
- Create the task, attribute via `cortex_update` as usual, and when the target
  came from a cortex task include `@<source-id>` in that update. THEN post ONE
  update on the source task too: `handover brief for this task's session
  pi-<uuid> → @<new-id>` — this is the one extra write this mode permits, so
  someone looking at the source task finds the brief.
- Bootstrap header `[SESSION_ID]` = the TARGET session id (the receiving agent
  resumes THAT work). Clipboard as usual.

### Rules (giving for another session)

- NEVER guess the target: ambiguous → ask; not found → stop and report.
- The transcript is the ONLY memory. No filling from this conversation.
- Read the WHOLE digest before writing; drill down for evidence you quote.
- READ-ONLY in the target repo (git status/log/diff, file reads). No
  builds/tests/services there.
- Writes: clipboard + ONE new cortex task + (only when sourced from a task) ONE
  cross-link update on the source task.
- Say when the session may still be live and when the repo has moved on.

### Return to the user (giving for another session)

**Handover complete (for another session).**
- **Origin session:** `<session_id>` — <session_name or first-request gist> (cwd `<session_cwd>`, last activity <last_activity>, <n> entries; <live/ended>)
- **Source:** <target as given → how it resolved>
- **Cortex task:** #<id> — <title> (lane `<lane>`, tag `handover`)<; cross-linked from #<source-id>>
- **Clipboard:** brief copied (<n> bytes)
- **Mission:** <one line>
- **Immediate next step:** <one line>
- **Confidence / gaps:** <what the transcript did not prove; repo drift since the session>

---

## Rules

- READ-ONLY except exactly TWO writes: the system clipboard and ONE cortex
  task (plus one cross-link update on the source task when handing off
  another session that came from / picked up a cortex task). NEVER modify project files, run git write commands, stage, or commit.
- NEVER fabricate progress or evidence. Unverified claims MUST be labeled.
- SELF-CONTAINED: assume the receiving agent has nothing but the brief.
- Preserve the user's original request VERBATIM.
- Prefer the `cortex_update` tool for attribution (resumable) over `--as`.
- Keep the cortex title to one concise mission-level line.
- Degrade gracefully: no session file / no `jq` -> synthesize from memory;
  no `cortex` -> clipboard only, and say so; no clipboard tool -> report the
  saved file path from `clip.sh`. EXCEPTION: when handing off ANOTHER session there is
  no memory to fall back on — without `jq` or the session file the resolver
  exits 1; STOP and tell the user instead of writing an ungrounded brief.
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
