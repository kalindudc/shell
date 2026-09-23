# Handover Brief — Structure & Authoring Guide

This is the artifact that goes to the clipboard AND becomes the body of the
cortex handoff task. It must be SELF-CONTAINED: a fresh agent in a brand-new
session, with ZERO prior context, must be able to read only this document and
continue the work correctly.

Fill every section. Omit a section only when it is genuinely empty, and when
you do, write `_none_` rather than deleting the heading — absence is signal.

Write in plain, dense prose and tight lists. No filler. Prefer exact paths,
exact commands, and quoted evidence over vague description. Preserve the
user's intent VERBATIM where the template asks for it — do not paraphrase the
original request.

---

## How this differs from generic `/compact` (why each section exists)

pi's compaction produces: Goal / Constraints / Progress / Key Decisions /
Next Steps / Critical Context / read-files / modified-files, and it KEEPS the
most recent ~20k tokens verbatim. A handover has no "kept recent messages" —
the receiving agent gets nothing but this brief. So this template adds the
context that compaction can safely omit but a cold-start agent cannot:

- Verbatim original request (compaction paraphrases; intent drifts).
- A resume runbook (repo/branch/build/test/services) so a cold agent can act.
- Mental model / architecture built up over the session.
- Rejected alternatives + gotchas (so the new agent avoids proven dead ends).
- Evidence attached to completed work (so "done" is trustworthy, not claimed).
- Provenance + a durable cortex task so the handoff is traceable and resumable.

---

## TEMPLATE (everything below the line is the brief itself)

---

<!-- BOOTSTRAP HEADER — include this ONLY in the clipboard + cortex-task copy.
     It tells the receiving agent how to use the brief. Keep it verbatim,
     filling the bracketed fields. -->

> HANDOVER — RESUME PRIOR WORK
> You are picking up work from a previous session with no shared memory.
> 1. Read this entire brief before doing anything.
> 2. Restate the mission and the immediate next step in your own words, and
>    confirm the plan with the user before making changes.
> 3. Durable copy + progress log: cortex task #[TASK_ID] (lane `[LANE]`).
>    Post updates there via the `cortex_update` tool as you work.
> 4. Provenance: repo `[REPO]`, branch `[BRANCH]`, origin session `[SESSION_ID]`.
>    (`[SESSION_ID]` is ALWAYS the session whose work you are resuming — for a
>    brief written for ANOTHER session (`/handover <target>`) that is the TARGET
>    session, not the one that wrote this.)

---

## 1. Mission (TL;DR)
[2-4 sentences: what this work is, where it stands right now, and the single
most important next action. A reader must grasp the situation in 15 seconds.]

## 2. Original Request (verbatim)
> [Paste the user's first request EXACTLY as written — do not fix or reword.]

Scope changes & clarifications since:
- [Any later instruction that changed or narrowed scope, quoted or tightly paraphrased. If none: _none_]

## 3. Constraints & Preferences
- [Hard requirements and explicit do's/don'ts the user stated.]
- [Conventions to honor: coding style, commit policy, comms style, tools to use/avoid.]
- [Things the user reacted negatively to — patterns to NOT repeat.]

## 4. Environment & Resume Runbook
- Repo root: [absolute path]
- Branch: [name]  (upstream: [name/none])  |  gh-stack layer: [yes/no]
- Working tree: [clean / list the dirty & untracked paths that matter]
- Base / merge-base for diffs: [ref]
- Build: `[command]`   Test: `[command]`   Lint/format: `[command]`
- Run / services to start: [command(s) or _none_]
- Tooling / versions / env that matters: [language, package manager, key deps, env vars]
- First orientation commands a fresh agent should run: [e.g. `git status`, `git diff <base>`, key file reads]

## 5. Mental Model / Architecture
[The understanding built up this session so the next agent does not re-derive
it. How the relevant components fit together; the key files and their roles;
data flow or control flow that matters; naming/pattern conventions in play.]

- `[path]` — [role / responsibility]
- `[path]` — [role / responsibility]

## 6. Work Completed (with evidence)
For each item: WHAT changed, WHY, and PROOF it works (quote the decisive test
or command output — not "it works").
- [x] [What] — [why] — evidence: `[quoted output / test result / verification]`
- [x] [What] — [why] — evidence: `[...]`

## 7. Modified & Key Files (current state)
- `[path]` — [created/edited/WIP]; [what is there now; for WIP, exactly what is half-done and what remains]
- `[path]` — [...]

## 8. Decisions & Rejected Alternatives
Decisions (with rationale):
- **[Decision]** — [why chosen]
Rejected / dead ends (do NOT re-explore):
- **[Approach]** — [why rejected / what failed], evidence: `[if any]`

## 9. Next Steps (ordered, actionable)
1. [The immediate next action — concrete and unambiguous. State the exact file/function/command.]
2. [Then this.]
3. [Then this.]
[Each step should be actionable without re-reading the whole conversation.]

## 10. Open Questions / Blockers / Risks
- Open question (needs user): [question + why it matters + your recommended default]
- Blocker: [what is blocked + on what]
- Risk / gotcha / footgun discovered: [the trap and how to avoid it]
[If none across the board: _none_]

## 11. Key Artifacts & References
- Files: [important paths not already listed]
- Commands worth reusing: `[command]` — [what it does]
- URLs / docs / tickets: [links]
- Related cortex tasks: [@id — relation]
- Error signatures to watch for: `[message]` — [meaning]

## 12. Provenance
- Origin session id: [PI_SESSION_ID]
- Cortex handoff task: #[TASK_ID] (lane `[LANE]`, tag `handover`)
- Repo / branch: [repo] / [branch]
- Generated: [UTC timestamp] by [provider/model]

Variant when the brief was written FOR ANOTHER SESSION (`/handover <target>`) — use
this block instead; every line matters for trust and traceability:
- Origin session id: [TARGET session id] — file `[session_file]`, cwd `[session_cwd]`
- Origin session name / first request gist: [session_name or one line]
- Source: [target as given → how it resolved, e.g. `task:370 → pi-01a0b072-…`]
- Snapshot as of: [last_activity of the origin session]; session looked [ended / POSSIBLY LIVE (file modified <n>s before generation)]
- Repo state observed at: [UTC timestamp] — [in sync with the session / has moved: head `[commit]` dated `[head_date]` is after last_activity]
- Other sessions on the source task (not covered by this brief): [pi-… (×n updates, last …); … or _none_]
- Generated by: session `[PI_SESSION_ID of the writer]` ([provider/model]) at [UTC timestamp], from the persisted transcript only — the writer did not participate in the origin session
- Cortex handoff task: #[TASK_ID] (lane `[LANE]`, tag `handover`)[; cross-linked from #[SOURCE_TASK_ID]]
