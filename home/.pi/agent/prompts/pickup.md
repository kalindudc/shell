---
description: Resume from a handover — pull a handover cortex task, consume its brief, and continue where the previous session left off
argument-hint: "<cortex-task-id>"
---

Load the `handover` skill and READ `~/.agents/skills/handover/references/receiving.md`, then follow it to resume from handover cortex task: $1

If `$1` is blank, run `cortex ls -t handover` and ask the user which task to resume — do NOT guess. Any extra user guidance after the id is binding: ${@:2}
