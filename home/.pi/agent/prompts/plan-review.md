---
description: Review an engineering implementation plan for correctness, completeness, and feasibility
---

Load the `plan-reviewer` skill and follow its instructions to review: $ARGUMENTS

## Explicit source

Use the provided Markdown path or Cortex task ID, including an unambiguous source already identified in the conversation. If no unique source is supplied, ask once. Report an invalid source directly; do not search for or substitute another plan.

## Subagent wiring

The selected skill owns factual verification and its registered `spawn` task-array mechanics. Do not repeat that work or dispatch to a separate consensus agent. Preserve the skill's fixed-quorum and degraded-output rules.

## Output

Use the skill's structured report contract, including an explicit answer-only/no-artifact request. Otherwise retain its configured review file and authorized clipboard behavior. Never mutate the source plan or its status.

## Rules

- Load the `plan-reviewer` skill and pass the explicit source through once.
- Verify source existence and ground findings in actual code, tests, and the reviewed plan snapshot.
- Never invent behavior or approve a plan without verifying factual claims.
