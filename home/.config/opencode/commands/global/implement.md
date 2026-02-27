---
description: Execute an implementation plan by systematically completing each task with verification
---

Load the `implementer` skill and follow its instructions to implement the plan: $ARGUMENTS

## Plan discovery

**IMPORTANT**: `./tmp/plan/` is gitignored. The Glob tool will NOT find files there. You MUST use `bash ls` or `bash find` for plan discovery — never Glob.

- If a directory is provided by the user, use `bash ls` to investigate if the directory contains any plans and prompt the user to select one to implement
- If a plan is not provided by the user, use `bash find ./tmp/plan/ -name '*.md' -type f 2>/dev/null` to discover existing plans and prompt the user to select one to implement
- If neither is provided or exists, prompt the user to provide a path to a plan
- If the user provided a plan and it does not exist, use `bash find ./tmp/plan/ -type f -name '*.md' 2>/dev/null` for a fuzzy search and look for similar plans and confirm with the user before proceeding

ALWAYS: give the user the opportunity to override a discovered plan with a custom one

## Rules

- **ALWAYS** load the `implementer` skill first for detailed instructions
- **ALWAYS** verify source files exist before reading
- **ALWAYS** use actual code and tests as source material
- **NEVER** invent or hallucinate code behavior
- **NEVER** skip verification steps between tasks
- **NEVER** continue past failures without user confirmation
