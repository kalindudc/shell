---
name: delegation
description: Strategy for automatically delegating work to minions for parallel execution, context isolation, and efficiency. Load this skill at the start of every session.
---

# Delegation Strategy

## Purpose

This skill defines WHEN and HOW to automatically delegate work to minions (spawned sub-agents). The goal is to keep the main context clean, parallelize independent work, and improve efficiency.

## When to Spawn Background Minions

ALWAYS delegate to background minions when:

- You have 2+ independent tasks with no data dependencies between them
- A subtask involves >10 tool calls that would pollute the main context (e.g., reading many files, broad search/exploration)
- Running tests, linting, or builds while continuing other work in the main thread
- Research or exploration tasks (reading documentation, searching codebases, investigating errors)
- Generating boilerplate or repetitive code across multiple files
- Tasks where you do NOT need the output immediately to continue

## When to Spawn Foreground Minions

ALWAYS delegate to foreground minions when:

- A subtask is complex but blocking -- you need the result before continuing
- You want to isolate context for a focused task (e.g., deep debugging a single module)
- The task is self-contained and its result feeds directly into your next step

## When NOT to Spawn

Do NOT delegate when:

- The task is a single command, single edit, or single file read
- You need the output immediately in the same thought to make a decision
- The user is interactively iterating on something and wants tight feedback loops
- The overhead of spawning exceeds the benefit (trivial tasks)

## Common Patterns

### Implementation Plans

When executing a plan with multiple independent tasks:
- Spawn one background minion per independent task
- Monitor progress with `list_minions` and `show_minion`
- Collect results and verify integration after all complete

### Code Review

When reviewing multiple files or modules:
- Spawn parallel minions, one per file or logical module
- Aggregate findings in the main context

### Test + Continue

When you need to run a test suite but have more work to do:
- Spawn a background minion to run and report test results
- Continue working in the main context
- Check results when the minion completes

### Research + Implement

When a task requires both research and implementation:
- Spawn a background minion to research (read docs, explore code, search)
- Begin implementation scaffolding in the main context
- Incorporate research findings when the minion completes

### Multi-file Edits

When making similar changes across many files:
- Group files into batches
- Spawn parallel minions, one per batch
- Verify consistency after all complete

## Task Descriptions

When spawning minions, write clear task descriptions that include:
- WHAT to do (specific and concrete)
- WHERE to do it (file paths, directories)
- HOW to verify (test commands, expected outputs)
- WHAT to return (summary of results, not raw output)

## Monitoring

- Use `list_minions` to check status of running minions
- Use `show_minion` to inspect a specific minion's progress
- Use `steer_minion` to redirect a minion if it goes off track
- Proactively check on long-running minions

## Context Hygiene

The primary reason to delegate is context hygiene. Every tool call in the main context consumes context window space. Delegating exploration, research, and multi-file operations to minions keeps the main context focused on decision-making and coordination.
