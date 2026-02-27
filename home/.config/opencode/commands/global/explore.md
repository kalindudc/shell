---
description: Rapidly explore and map an unfamiliar codebase
agent: codebase-explorer
subtask: true
---

Load the `codebase-explorer` skill and follow its instructions to explore this codebase: $ARGUMENTS

Here is the current directory structure to start:
!`ls -la`

If no specific question is provided, produce a concise structured overview of the codebase.

## Rules

- **ALWAYS** load the `codebase-explorer` skill first for detailed instructions
- **ALWAYS** include file:line references for every factual claim
- **NEVER** modify source files -- only write to `./tmp/`
