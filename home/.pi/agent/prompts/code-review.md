---
description: Review a PR for bugs, security issues, and logic errors with multi-stage filtering
---

Load the `pr-reviewer` skill and follow its instructions to review: $ARGUMENTS

## PR context

Use an explicit PR URL/number or supplied pinned context before inferring the current PR. If no unique source is available, ask once. The skill owns metadata/diff/comment retrieval and revision checks; do not duplicate them or change the user's checkout to begin review.

## Subagent wiring

The skill owns bounded investigation and registered `spawn` task-array batching. Do not dispatch to a separate consensus agent or repeat its verification stages. Preserve fixed distinct-model quorum and degraded-output rules.

## Plan linking

- Plans are NOT auto-discovered for reviews. If the user wants the review linked to a plan, they MUST specify the cortex plan id in `$ARGUMENTS` (e.g., `plan #42`, `--plan 42`, or `for plan 42`).
- When a plan id is supplied, the skill inherits the plan's tags (except the reserved `plan` tag) and posts a `@<PLAN_ID>` linking update on the review task.

## Output

- Retain the configured Cortex draft product when authorized, with `pr-review` and supplied-plan tags except reserved `plan`; the skill owns persistence, attribution, and linking.
- Honor an explicit answer-only/no-external-records request with an inline review and no Cortex or clipboard writes.
- Never post comments directly on the PR; the user decides what to post.

## Rules

- Load the `pr-reviewer` skill and pass the explicit source through once.
- Verify findings against relevant source/callers/contracts and tests; do not invent behavior or assume the active checkout is the PR revision.
- Use applicable validation evidence or relevant authorized non-modifying checks. Do not mandate checkout, installation, or a build/test/lint cycle; report unperformed validation and blockers.
- Report bugs, security issues, and logic errors, not style or theoretical redesign.
- Never auto-discover plans; link only an explicitly named plan.
