---
description: Hand off a conversation — THIS one by default, or another session when the first argument names it — as a self-contained brief on the clipboard + a durable resumable cortex task; inside Herdr the pickup is auto-started in a new pane
argument-hint: "[target] [focus instructions]"
---

Load the `handover` skill (read its SKILL.md in full) and follow it. Arguments: $ARGUMENTS

- If the FIRST argument names another session (a `.jsonl` path, cortex task id, `pi-<uuid>` tag, or session uuid/prefix — the skill's router has the exact grammar), follow the skill's pointer to `references/giving-foreign.md` and hand off THAT session from its transcript.
- Otherwise hand off THIS conversation using the skill's main giving-side flow.
- The user's remaining arguments are focus text: let them steer the brief's emphasis; never drop mandatory sections.

Degrade exactly as the skill says (no cortex → clipboard only; foreign mode with no transcript → STOP). Return: cortex task id + title, which session was handed off, clipboard confirmation, mission, immediate next step.
