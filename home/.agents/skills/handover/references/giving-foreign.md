# Giving for another session (/handover <target> [focus])

Loaded from SKILL.md when the FIRST `/handover` argument names a session you
did NOT participate in — a minion's run, a colleague's session on this
machine, an earlier session that was never handed off, or the session(s) that
posted updates on a cortex task. You have ZERO memory of that conversation:
its persisted transcript is the only source of truth.

Goal: produce the same two deliverables as the main flow (clipboard brief +
cortex task), grounded ONLY in the target transcript.

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
  `/handover` flow in SKILL.md.

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

Read `references/brief-template.md` and follow it exactly, with these
differences:

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
- Create the task with `cortex add … -t handover` and attribute via the
  `cortex_update` tool as usual; when the target came from a cortex task
  include `@<source-id>` in that update. THEN post ONE update on the source
  task too: `handover brief for this task's session pi-<uuid> → @<new-id>` —
  this is the one extra write this mode permits, so someone looking at the
  source task finds the brief.
- Bootstrap header `[SESSION_ID]` = the TARGET session id (the receiving agent
  resumes THAT work). Clipboard as usual.
- Then run "Phase 4 — Herdr auto-pickup" exactly as in SKILL.md, with the new
  pane's `--cwd` = the TARGET session's cwd when `cwd_state` says it exists on
  this machine (else `$PWD`, and say so in the return message).

### Rules (in addition to the shared rules in SKILL.md)

- NEVER guess the target: ambiguous → ask; not found → stop and report.
- The transcript is the ONLY memory. No filling from this conversation.
- Read the WHOLE digest before writing; drill down for evidence you quote.
- READ-ONLY in the target repo (git status/log/diff, file reads). No
  builds/tests/services there.
- Writes: clipboard + ONE new cortex task + (only when sourced from a task)
  ONE cross-link update on the source task + (inside Herdr only) the Phase 4
  pane split / `agent start` / `agent prompt`.
- Say when the session may still be live and when the repo has moved on.

### Return to the user (giving for another session)

**Handover complete (for another session).**
- **Origin session:** `<session_id>` — <session_name or first-request gist> (cwd `<session_cwd>`, last activity <last_activity>, <n> entries; <live/ended>)
- **Source:** <target as given → how it resolved>
- **Cortex task:** #<id> — <title> (lane `<lane>`, tag `handover`)<; cross-linked from #<source-id>>
- **Clipboard:** brief copied (<n> bytes)
- **Herdr:** pickup running in pane `<pane-id>` as agent `pickup-<id>`, focus moved there | skipped — not inside Herdr | failed: <verbatim error>
- **Mission:** <one line>
- **Immediate next step:** <one line>
- **Confidence / gaps:** <what the transcript did not prove; repo drift since the session>
