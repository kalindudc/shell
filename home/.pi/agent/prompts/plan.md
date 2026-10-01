---
description: Creates a structured plan for implementing a vertical slice of working software
---

Load the `cortex-planner` skill and follow its instructions to create a comprehensive plan for: $ARGUMENTS

## Independent review

The planner verifies claims itself and lists its design claims in the plan's Verification Notes; it does not run a multi-model review. Once the plan task exists, load the `plan-reviewer` skill and review that Cortex task id, giving its design claims priority. Report the verdict with the task id. Never edit the plan body or its status.

## Rules

- **ALWAYS** load the `cortex-planner` skill first for detailed instructions
- **ALWAYS** verify source files exist before reading
- **ALWAYS** use actual code and tests as source material
- **NEVER** invent or hallucinate code behavior
- **NEVER** exceed 128 characters for output filename
