---
description: Hand off a conversation — THIS one by default, or another session when the first argument names it — as a self-contained brief on the clipboard + a durable resumable cortex task; inside Herdr the pickup is auto-started in a new pane
argument-hint: "[target] [focus instructions]"
---

Load the `handover` skill and follow it to hand off a conversation so a fresh agent, in a brand-new session with zero prior context, can continue it. Arguments: $ARGUMENTS

## Which session gets handed off (decide this FIRST, from the arguments alone)

Look at the FIRST whitespace-separated token of the arguments:

- It is a **session target** if it is a session `.jsonl` path (contains `/` or ends in `.jsonl`), a cortex task id (`#370`, `370`, `task:370`), a `pi-<uuid>` attribution tag, or a pi session uuid / uuid prefix (≥ 8 hex chars). Then hand off THAT session: run the skill's `scripts/resolve-session.sh <target>` and follow its "Giving for another session" section, grounding ONLY in that session's persisted transcript. Everything after the target is focus text. Do NOT tell the user to run some other command — this prompt is the only handover entry point. If the resolver reports `is_current: yes`, the target is this conversation: fall back to the normal flow below. Ambiguous → show the resolver's candidate table and ask; not found → stop and report the exact error.
- Otherwise (no arguments, or plain prose): hand off THIS conversation. All arguments are focus text.

A path pasted with a stray space or line-wrap (e.g. `2026-09- 21T…`) is still a target — repair it and verify the file exists before resolving.

## Produce

- A SELF-CONTAINED handover brief copied to the system clipboard (paste-ready for a new pi session).
- A durable, resumable cortex task (lane = repo, tag `handover`, status `open`) whose body is the same brief.

## Rules

- **ALWAYS** load the `handover` skill first for the full methodology.
- **ALWAYS** ground the brief in facts from `scripts/collect-context.sh` (session file + git + cortex) — never memory alone. For THIS conversation, recover anything auto-compaction dropped and fold in prior compaction/branch summaries. For ANOTHER session, the transcript digest is the only memory — read all of it and never fill gaps from this conversation.
- **ALWAYS** preserve the user's original request VERBATIM (the target session's first user message when handing off another session).
- **ALWAYS** make the brief self-contained — assume the receiving agent has zero prior context.
- **ALWAYS** attach evidence to every completed item; **NEVER** fabricate progress or claim success without proof. Label transcript claims you could not verify.
- **ALWAYS** attribute the cortex task via the `cortex_update` tool (resumable), not `cortex update --as`.
- **READ-ONLY** except: the system clipboard, ONE new cortex task, and — only when the target came from a cortex task or is a `/pickup` of one — ONE cross-link update on that source task. **NEVER** modify project files, run git write commands, or commit.
- Honor the focus text as emphasis/ordering for the brief; never drop mandatory sections.
- Degrade gracefully: no session file/`jq` → synthesize from context (THIS conversation only; for another session, stop and say so); no `cortex` → clipboard only (say so); no clipboard tool → report the saved file path.
- Return the cortex task ID, confirmation the brief is on the clipboard, which session was handed off, the mission, and the immediate next step.
