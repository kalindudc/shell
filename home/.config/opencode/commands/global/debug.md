---
description: Investigate a bug or unexpected behavior using scientific debugging
agent: debugger
---

Load the `debugger` skill and follow its instructions to investigate: $ARGUMENTS

Recent changes for context:
!`git log --oneline -10`
!`git diff --stat HEAD~3`

If the user provides a Buildkite URL or CI failure reference, use the `buildkite-mcp` tools to gather job logs before beginning the investigation.

## Rules

- **ALWAYS** load the `debugger` skill first for detailed instructions
- **ALWAYS** try to reproduce the problem before investigating
- **ALWAYS** present hypotheses to the user before pursuing them
- **NEVER** modify source files -- only write to `./tmp/`
