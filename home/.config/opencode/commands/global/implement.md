---
description: Execute an implementation plan by systematically completing each task with verification
---

Load the `implementer` skill and follow its instructions to implement the plan: $ARGUMENTS

If no plan file is provided in the arguments, ask the user to specify the exact path to the plan file.

## Rules

- **ALWAYS** load the `implementer` skill first for detailed instructions
- **ALWAYS** verify source files exist before reading
- **ALWAYS** use actual code and tests as source material
- **NEVER** invent or hallucinate code behavior
- **NEVER** skip verification steps between tasks
- **NEVER** continue past failures without user confirmation
