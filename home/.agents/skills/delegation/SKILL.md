---
name: delegation
description: Strategy for delegating substantial work to minions when independent subtasks or context isolation justify the overhead.
---

# Delegation

## Activation and Reuse

Use this skill for substantial work where independent subtasks or context isolation justify delegation. Do not load it merely because a session began or a task has multiple steps. Direct replies and bounded work need no automatic delegation setup.

Reuse guidance already in context; reload only if it has changed or is no longer in context.

## When to Spawn

Use `spawn` when substantial independent work or context isolation has a concrete benefit:
- Independent questions can be answered without shared writes or data dependencies.
- A bounded investigation benefits from a focused context rather than duplicating evidence already available to the parent.
- A complex subtask can return a useful, verifiable result that supports the next decision.

Use only registered delegation capabilities. In Pi, `spawn` is foreground with a nonempty `tasks` array; one call can run independent tasks in parallel and returns when they finish. Do not invent a background tool or promise that the parent can continue while the foreground call is blocked.

Task-array template (replace placeholders with verified paths and concrete questions):

```json
{"tasks":[{"task":"In <repo>/module-a, verify <claim A> against source and tests without edits; return findings with file:line evidence and uncertainty."},{"task":"In <repo>/module-b, verify independent <claim B> against source and tests without edits; return findings with file:line evidence and uncertainty."}]}
```

## When NOT to Spawn

- Single command, single edit, or single file read
- You need the output in the same thought to make a decision
- User is interactively iterating and wants tight feedback loops
- Overhead exceeds benefit (trivial tasks)

## Common Patterns

- Plan execution: delegate independent scopes with disjoint file ownership; the parent verifies integration.
- Research/review: group related questions and evidence, rather than creating a child for each small claim.
- Verification: run a simple check inline; delegate only when isolation or substantial independent work justifies the coordination cost.
- Multi-file edits: batch related files under one owner and wait for dependent results before continuing.

## Task Descriptions

Every minion task MUST include:
- WHAT to do — specific and concrete
- WHERE — file paths, directories, URLs
- HOW to verify — test commands, expected outputs
- WHAT to return — summary of results, not raw output
