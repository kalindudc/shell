---
description: Hand off THIS conversation — self-contained brief to clipboard + a durable resumable cortex task for a fresh session
argument-hint: "[focus instructions]"
---

Load the `handover` skill and follow its instructions to hand off THIS conversation so a fresh agent, in a brand-new session with zero prior context, can continue it. Optional focus: $ARGUMENTS

## Produce

- A SELF-CONTAINED handover brief copied to the system clipboard (paste-ready for a new pi session).
- A durable, resumable cortex task (lane = repo, tag `handover`, status `open`) whose body is the same brief.

## Rules

- **ALWAYS** load the `handover` skill first for the full methodology.
- **ALWAYS** ground the brief in facts from `scripts/collect-context.sh` (session file + git + cortex) — never memory alone. Recover anything auto-compaction dropped from your live context, and fold in any prior compaction/branch summaries.
- **ALWAYS** preserve the user's original request VERBATIM.
- **ALWAYS** make the brief self-contained — assume the receiving agent has zero prior context.
- **ALWAYS** attach evidence to every completed item; **NEVER** fabricate progress or claim success without proof.
- **ALWAYS** attribute the cortex task via the `cortex_update` tool (resumable), not `cortex update --as`.
- **READ-ONLY** except two writes: the system clipboard and ONE cortex task. **NEVER** modify project files, run git write commands, or commit.
- Honor `$ARGUMENTS` as focus/emphasis for the brief.
- Degrade gracefully: no session file/`jq` → synthesize from context; no `cortex` → clipboard only (say so); no clipboard tool → report the saved file path.
- Return the cortex task ID, confirmation the brief is on the clipboard, the mission, and the immediate next step.
