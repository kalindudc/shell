---
description: Generate a structured PR description from the current branch's changes
---

Load the `pr-description-generator` skill and follow its instructions to generate a PR description: $ARGUMENTS

## Context gathering

- Detect parent branch: check if graphite CLI is available (`which gt`), use `gt log` for stacked branches. Fall back to git-based parent detection otherwise.
- Gather the diff: `git diff <parent>...HEAD` and `git log --oneline <parent>...HEAD`
- Use `git_diff_summary` for a structured overview of changes with file categorization
- Discover related plans in cortex (same lane = repo dir name, tag = `plan`):
  ```bash
  LANE=$(git rev-parse --show-toplevel 2>/dev/null | xargs basename || basename "$PWD")
  cortex ls --lane "$LANE" -t plan --json
  ```
  Match plans against the current branch (slug overlap between branch name, plan title, plan updates, plan body). If multiple plausible matches exist, prompt the user. If none match, proceed without a plan reference.

## Output

- Persist the PR description as a cortex task in the repo lane with status `draft`, tagged `pr-desc` plus every tag carried by the related plan (if one was discovered) EXCEPT the reserved `plan` tag. See the skill for the exact `cortex add --body-file` recipe and the post-create attribution + plan-linking updates.
- Copy the PR description body to clipboard via `pbcopy` if available.

## Rules

- ALWAYS load the `pr-description-generator` skill first for detailed instructions
- ALWAYS verify description-code alignment -- every claim must match actual changes
- NEVER invent or hallucinate code behavior
- NEVER over-reference related issues/PRs -- omit if unsure
- ALWAYS follow the brevity constraint -- readable in under 5 minutes
- ALWAYS use `skill-improver` to capture observations after skill execution completes
