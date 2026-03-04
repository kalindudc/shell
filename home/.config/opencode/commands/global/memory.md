---
description: Analyze past session memory for usage patterns, costs, and history
agent: memory-analyzer
subtask: true
---

Load the `memory-analyzer` skill and follow its instructions to analyze: $ARGUMENTS

Here is the current session index for immediate context:
!`cat ~/.config/opencode/memory/index.json 2>/dev/null || echo '{"error": "No memory data found. No sessions have been recorded yet."}'`

If no specific question is provided, produce a summary of overall usage statistics. If no memory data exists, inform the user that no sessions have been recorded yet.

## Rules

- **ALWAYS** load the `memory-analyzer` skill first for detailed instructions
- **NEVER** modify memory files -- read-only analysis
- **ALWAYS** label cost estimates as approximate
- **ALWAYS** use `@skill-improver` to capture observations after skill execution completes
