---
description: Review an engineering implementation plan for correctness, completeness, and feasibility
---

Load the `plan-reviewer` skill and follow its instructions to review: $ARGUMENTS

## Plan discovery

**IMPORTANT**: `./tmp/plan/` is gitignored. The Glob tool will NOT find files there. You MUST use `bash ls` or `bash find` for plan discovery — never Glob.

- If a plan path is provided by the user, use that directly
- If a directory is provided by the user, use `bash ls` to list plans and prompt the user to select one
- If no plan is provided, use `bash find ./tmp/plan/ -name '*.md' -type f 2>/dev/null` to discover existing plans and prompt the user to select one to review
- If the user provided a plan and it does not exist, use `bash find ./tmp/plan/ -type f -name '*.md' 2>/dev/null` for a fuzzy search and confirm with the user before proceeding

ALWAYS: give the user the opportunity to override a discovered plan with a custom one

## Subagent wiring

- For factual claim verification (Correctness dimension), use the `researcher` agent via the subagent tool
- For Blocker/Concern filtering (consensus step), use the `consensus` agent via the subagent tool. If the consensus agent is not available, the skill handles graceful degradation -- retain all findings and note the skip in the output.

## Output

- Write the structured review to `./tmp/plan-review/<plan-name>-review.md`
- Copy to clipboard via `pbcopy` if available

## Rules

- **ALWAYS** load the `plan-reviewer` skill first for detailed instructions
- **ALWAYS** verify source files exist before reading
- **ALWAYS** use actual code and tests as source material
- **NEVER** invent or hallucinate code behavior
- **NEVER** approve a plan without verifying factual claims
- **ALWAYS** use `skill-improver` to capture observations after skill execution completes
