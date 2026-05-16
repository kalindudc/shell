---
description: Execute an implementation plan by systematically completing each task with verification
---

Load the `cortex-implementer` skill and follow its instructions to implement the plan: $ARGUMENTS

## Plan discovery

- If a `lane` is provided by the user, use `cortex ls -l <lane> -t plan -s open` to investigate if the lane contains any open tasks and ask the user which to implement
- If nothing is provided by the user, find the current `lane` as the current git repo or current directory and use `cortex ls -l <lane> -t plan -s open` to investigate if the lane contains any open taks and ask the user which to implement

ALWAYS: give the user the opportunity to override a discovered plan with a custom one

## Rules

- **ALWAYS** load the `cortex-implementer` skill first for detailed instructions
- **ALWAYS** verify source task exist before reading and that it is in an `open` state
- **ALWAYS** use actual code and tests as source material
- **NEVER** invent or hallucinate code behavior
- **NEVER** skip verification steps between tasks
- **NEVER** continue past failures without user confirmation
