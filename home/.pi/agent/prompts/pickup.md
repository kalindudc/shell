---
description: Resume from a handover — pull a handover cortex task, consume its brief, and continue where the previous session left off
argument-hint: "<cortex-task-id>"
---

Load the `handover` skill and follow its "Receiving side (/pickup)" instructions to resume from handover cortex task: $1

Full user response: $ARGUMENTS

## Pre-requisites (run in order; stop at the first failure)

1. **Require a task id.** The requested id is `$1`. If that is blank, run `cortex ls -t handover` and ask the user which handover task to resume — do NOT guess.
2. **Pull the task.** Run `cortex show $1 --json | jq -r '.task.title, .task.status, (.task.tags|join(",")), "----", .task.body'`. If it errors or the id is not found, STOP and tell the user.
3. **Sanity-check the tag.** If `.task.tags` does not include `handover`, warn the user and continue only on their confirmation.

## Rules

- **ALWAYS** load the `handover` skill first and follow its receiving-side methodology.
- **ALWAYS** consume the WHOLE brief, then orient READ-ONLY in the repo (`git status`/`branch`/`diff` + the key files it lists) before doing anything.
- **ALWAYS** reconcile the brief against current repo reality — CURRENT STATE WINS; flag every material discrepancy to the user.
- **ALWAYS** restate the mission + immediate next step and CONFIRM with the user before making changes.
- **ALWAYS** post a `cortex_update` (resumable tool) noting the resumption; update status as work progresses (`done` when complete, `blocked` if stuck).
- **READ-ONLY** until the user confirms the plan; then honor their git protocol (NEVER commit unless asked).
- **NEVER** re-explore approaches the brief lists as rejected / dead ends.
- Honor any extra guidance the user passes after the id: ${@:2}
