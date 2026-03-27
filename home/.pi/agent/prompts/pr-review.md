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

## Output

- Write the structured review to `./tmp/pr-review/<pr-number>-review.md`
- Copy to clipboard via `pbcopy` if available
- **NEVER** post comments directly on the PR -- the user decides what to post

## Rules

- **ALWAYS** load the `pr-reviewer` skill first for detailed instructions
- **ALWAYS** read changed files in full context, not just diff hunks
- **ALWAYS** run tests/build as validation
- **NEVER** report style, formatting, or theoretical concerns -- bugs only
- **NEVER** post comments directly on the PR
- **ALWAYS** use `skill-improver` to capture observations after skill execution completes
