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
{"tasks":[{"agent":"researcher","task":"In <repo>/module-a, verify <claim A> against source and tests without edits; return findings with file:line evidence and uncertainty."},{"agent":"researcher","task":"In <repo>/module-b, verify independent <claim B> against source and tests without edits; return findings with file:line evidence and uncertainty."}]}
```

Name a persona on each task, or set its `model`, to choose the minion's model (see Model Selection).

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

## Model Selection

Pick the model by naming a persona on the task, not by leaving it to inherit yours. A minion with no `agent` and no `model` runs on the caller's model, which is usually the most expensive one in the session. Verified 2026-11-09 against a week of spend: delegated work on the caller's Opus 5.5 was over a third of it.

| Work | Persona | Model |
|---|---|---|
| Implementation from a clear brief: planned features, fixes, refactors, test runs | `builder` | GPT-6.1 Sol, xhigh |
| Read-only research: code questions, docs, web, inventories | `researcher` | Claude Sonnet 5.5, high |
| Designing a UI: job brief, HTML mock, production UI (the `ux-design` skill) | `ux-designer` | Claude Opus 5.5, high |
| Reviewing a UI brief, mock or shipped page, independent of its designer | `ux-reviewer` | GPT-6 Astra, high |
| Verifying findings in a PR review or critique | `verifier` | the caller's own model |
| Critics in a PR review or critique | none | the `model` and `thinking` in `critique/critics.yml` |

- Leave `agent` and `model` unset, so the minion runs on your own model, only for work that needs that judgment: a design decision, a high-risk or high-impact change, or a model the user asked for. Say why in the task.
- PR reviews keep their models. NEVER move a reviewer, verifier or critic to a cheaper model to save cost.
- A task's `model` overrides the persona's. When a builder or researcher result is not good enough, rerun it once on your own model rather than escalating through several models.
- On a machine without these providers, list the usable models with `python3 ~/.agents/skills/delegation/discover-models.py` (it asks the local pi for its live registry, with prices) and set the persona's `model` to the nearest equivalent: a model at about half the price of the flagship for `builder` and `researcher`.

## Task Descriptions

Every minion task MUST include:
- WHAT to do — specific and concrete
- WHERE — file paths, directories, URLs
- HOW to verify — test commands, expected outputs
- WHAT to return — summary of results, not raw output

For the `researcher` agent, also give numbered questions, exact paths/revisions/URLs, a tool-call budget (e.g. "~15 tool calls"), and explicit non-scope (e.g. "no full-file review"). Split broad sweeps into focused researchers: broad assignments exhaust their turns and return progress instead of findings.
