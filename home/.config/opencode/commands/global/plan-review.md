---
description: Perform a thorough, structured review of an engineering implementation plan
---

Load the `plan-reviewer` skill and follow its instructions to review the plan: $ARGUMENTS

## Plan discovery

**IMPORTANT**: `./tmp/plan/` is gitignored. The Glob tool will NOT find files there. You MUST use `bash ls` or `bash find` for plan discovery — never Glob.

- If a path is provided by the user, use that directly
- If a directory is provided, use `bash ls` to list plans and prompt the user to select one
- If no plan is provided, use `bash find ./tmp/plan/ -name '*.md' -type f 2>/dev/null` to discover existing plans and prompt the user to select one to review
- If the provided plan does not exist, use `bash find ./tmp/plan/ -type f -name '*.md' 2>/dev/null` for a fuzzy search and look for similar plans, confirm with the user before proceeding
- If neither is provided or exists, prompt the user to provide a path to a plan

ALWAYS: give the user the opportunity to override a discovered plan with a custom one

## Rules

- **ALWAYS** load the `plan-reviewer` skill first for detailed instructions
- **ALWAYS** verify the plan file exists before reading
- **ALWAYS** verify factual claims in the plan against the actual codebase
- **NEVER** approve a plan without completing the review process
- **NEVER** modify the plan file -- the review is read-only; output goes to `./tmp/plan-review/`
- **ALWAYS** use `@skill-improver` to capture observations after skill execution completes
