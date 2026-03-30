---
name: delegation
description: Strategy for delegating work to minions for parallel execution and context isolation. Use at the start of every session and before any multi-step task.
---

# Delegation

## When to Spawn

Use `spawn` for most delegation — including parallel execution. Multiple `spawn` calls in a single response run concurrently and return together:
- 2+ independent tasks with no data dependencies
- Subtask involves >10 tool calls (broad search, reading many files, exploration)
- Complex subtask whose output feeds into your next step
- Context isolation for focused work (deep debugging, single-module analysis)

Use `spawn_bg` only for long-running work that you do not need immediately:
- Lengthy research or documentation gathering while you continue other work
- Running full test suites or builds while continuing implementation
- Fire-and-forget tasks where results are consumed later

## When NOT to Spawn

- Single command, single edit, or single file read
- You need the output in the same thought to make a decision
- User is interactively iterating and wants tight feedback loops
- Overhead exceeds benefit (trivial tasks)

## Common Patterns

- **Plan execution**: one minion per independent task, verify integration after all complete
- **Code review**: parallel minions per file or module, aggregate findings
- **Test + continue**: `spawn_bg` for tests, main context continues working
- **Research + implement**: `spawn_bg` for research, main context scaffolds, incorporate findings when ready
- **Multi-file edits**: group files into batches, one minion per batch

## Task Descriptions

Every minion task MUST include:
- WHAT to do — specific and concrete
- WHERE — file paths, directories, URLs
- HOW to verify — test commands, expected outputs
- WHAT to return — summary of results, not raw output
