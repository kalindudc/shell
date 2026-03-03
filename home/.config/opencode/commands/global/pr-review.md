---
description: Perform a structured, research-backed review of a pull request
---

Load the `pr-reviewer` skill and follow its instructions to review: $ARGUMENTS

Here is the current git context:
!`git log --oneline -5`
!`git branch --show-current`

## Pre-requisites

Run these checks **in order** before loading the skill. Stop at the first failure.

1. **Resolve PR identifier**: Extract a PR number or URL from `$ARGUMENTS`. If missing, prompt the user to provide a PR number or a full link to the PR that can be used to extract the PR number.
2. **Verify repo**: Use `gh pr view <number> --json url,headRepository` to get the PR's repository. Confirm the current working directory is a clone of that repo (compare `gh repo view --json nameWithOwner` against the PR's repo). If it does not match, **EXIT** and tell the user to `cd` into the correct repo clone and rerun.
3. **Verify PR exists**: If `gh pr view` fails, the PR does not exist or is not accessible. **EXIT** with the error.
4. **Checkout remote branch**: Fetch and checkout the PR's head branch from the remote so file reads reflect the PR's code: `gh pr checkout <number>`. This ensures the review is done against the actual PR code, not stale local state.

## Rules

- **ALWAYS** load the `pr-reviewer` skill first for detailed instructions
- **ALWAYS** complete all pre-requisites before starting the review
- **NEVER** post comments directly on the PR without user approval
- **ALWAYS** output the review for the user to decide what to post
- **ALWAYS** use `@skill-improver` to capture observations after skill execution completes
