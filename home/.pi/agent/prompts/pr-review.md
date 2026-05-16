---
description: Review a PR for bugs, security issues, and logic errors with multi-stage filtering
---

Load the `pr-reviewer` skill and follow its instructions to review: $ARGUMENTS

## PR context gathering

- Auto-detect the current PR number: `gh pr view --json number -q .number`
- If no PR is found and no number was provided in `$ARGUMENTS`, prompt the user
- Checkout the PR branch: `gh pr checkout <number>`
- Fetch the PR diff, metadata, and existing comments as described in the skill's Stage 1

## Subagent wiring

- For deep investigation of potential findings (Stage 2), use the `researcher` agent via the subagent tool
- For finding filtering (Stage 3 consensus), use the `consensus` agent via the subagent tool. If the consensus agent is not available, the skill handles graceful degradation -- retain researcher-verified findings and note the skip in the output.

## Plan linking

- Plans are NOT auto-discovered for reviews. If the user wants the review linked to a plan, they MUST specify the cortex plan id in `$ARGUMENTS` (e.g., `plan #42`, `--plan 42`, or `for plan 42`).
- When a plan id is supplied, the skill inherits the plan's tags (except the reserved `plan` tag) and posts a `@<PLAN_ID>` linking update on the review task.

## Output

- Persist the structured review as a cortex task in the repo lane with status `draft`, tagged `pr-review` plus every tag carried by the user-specified plan (if one was provided) EXCEPT the reserved `plan` tag. See the skill for the exact `cortex add --body-file` recipe and the post-create attribution + plan-linking updates.
- Copy the review body to clipboard via `pbcopy` if available
- NEVER post comments directly on the PR -- the user decides what to post

## Rules

- ALWAYS load the `pr-reviewer` skill first for detailed instructions
- ALWAYS read changed files in full context, not just diff hunks
- ALWAYS run tests/build as validation
- NEVER report style, formatting, or theoretical concerns -- bugs only
- NEVER post comments directly on the PR
- NEVER auto-discover plans -- only link to a plan when the user explicitly names one
- ALWAYS use `skill-improver` to capture observations after skill execution completes
