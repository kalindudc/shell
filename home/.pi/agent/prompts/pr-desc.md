---
description: Generate a structured PR description from the current branch's changes
---

Load the `pr-description-generator` skill and follow its instructions to generate a PR description: $ARGUMENTS

## Context gathering

- Detect parent branch: check if graphite CLI is available (`which gt`), use `gt log` for stacked branches. Fall back to git-based parent detection otherwise.
- Gather the diff: `git diff <parent>...HEAD` and `git log --oneline <parent>...HEAD`
- Use `git_diff_summary` for a structured overview of changes with file categorization
- Check `./tmp/plan/` for related plan files that explain the intent behind the changes. Use `bash find ./tmp/plan/ -name '*.md' -type f 2>/dev/null` to discover plans. If multiple plans exist and the relevant one is ambiguous, prompt the user.

## Output

- Write the PR description to `./tmp/pr/<branch_name>-pr.md` (truncate branch name to 60 chars)
- Copy to clipboard via `pbcopy` if available

## Rules

- **ALWAYS** load the `pr-description-generator` skill first for detailed instructions
- **ALWAYS** verify description-code alignment -- every claim must match actual changes
- **NEVER** invent or hallucinate code behavior
- **NEVER** over-reference related issues/PRs -- omit if unsure
- **ALWAYS** follow the brevity constraint -- readable in under 5 minutes
- **ALWAYS** use `skill-improver` to capture observations after skill execution completes
