---
description: Execute an implementation plan by systematically completing each task with verification
---

Load the `cortex-implementer` skill and follow its instructions to implement the plan: $ARGUMENTS

## Explicit plan input

Use the Cortex task ID the user provided, including an unambiguous explicit reference to a task already identified in the conversation. If no task is identified, ask for its ID once and wait. Do not enumerate lanes, select a plausible plan, or create a replacement plan.

The skill owns status/coordination checks and execution. Do not re-confirm an already authorized, explicit handoff solely because planning notes exist.

## Rules

- Load the `cortex-implementer` skill for its execution contract.
- Verify the named task exists and follow its status gate; `open` or explicit authorization permits execution.
- Use actual code and tests as evidence; never invent code behavior or verification results.
- Follow the skill's bounded, safe retry and baseline-acceptance rules; ask when authorization or a nontrivial scope change requires it.
