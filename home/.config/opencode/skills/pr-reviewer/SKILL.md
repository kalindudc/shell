---
name: pr-reviewer
description: Minimal, actionable PR reviews with findings, validation, and checklist
---

# PR Reviewer Skill

## Purpose

Review PRs for code health. Output a minimal, actionable review -- not inline PR comments. The user decides what to post.

Goal: "Would merging this improve the codebase?"

## Process

### 1. Fetch PR context

Pre-requisites already resolved the PR and checked out the remote branch. If `gh pr checkout` fails (deleted branch), use `gh pr view --json headRefOid` + `git checkout <sha> --detach`.

- `gh pr view <number> --json title,body,author,baseRefName,headRefName,files,additions,deletions,url`
- `gh pr diff <number>` -- the authoritative diff source. Prefer over `git-diff-summary` for scope (it can include merged-in changes on diverged branches).
- For merged-main branches: use three-dot diff (`git diff base...HEAD`) and `gh pr view --json commits` to disambiguate PR-specific changes from merged-in noise
- `git_blame_context` on critical changed regions for prior change rationale
- If PR references an issue, fetch via `gh issue view`

### 2. Understand the change

- Read PR description for intent
- Read changed files in full context (not just diff hunks)
- Use `ast_query` for structural patterns if needed
- Use `@codebase-explorer` if codebase is unfamiliar
- Identify: problem, approach, alternatives

### 3. Evaluate

Check only dimensions that apply: design, functionality, complexity, tests, naming, style, docs.

Scan for hidden artifacts: whitespace/alignment hunks hiding unrelated additions, AI-injected URL tracking params (`?utm_source=openai`), dead code introduced via conflict resolution.

### 4. Validate

Run the project's test suite and any relevant build/lint commands. Read repo guidelines for test execution. Record each command and its outcome.

### 5. Findings

Categorize into three buckets:

- **Major concerns** -- must fix or should fix (bugs, security, design issues, missing tests)
- **Suggestions** -- would improve but not blocking
- **Praise** -- something done well

Keep each finding to one line: `file:line -- what and why`. No filler.

## Output

Write to `./tmp/pr-review/<pr-number>-review.md`:

```markdown
# PR #<number> - <title>

Author: <author> | <base> -> <head>
Verdict: Approve / Request Changes / Comment

## Summary

<2-3 sentences. What the PR does and overall assessment.>

## Findings

### Major concerns
- `file:line` -- description
(or: None)

### Suggestions
- `file:line` -- description
(or: None)

### Praise
- `file:line` -- description

## Validation
- `<command>` -- <result, e.g. "42 tests passed", "build ok", "lint clean">
- `<command>` -- <result>

## Checklist
- [x] Design
- [x] Functionality
- [x] Tests
- [~] Docs (not applicable)

(only dimensions evaluated: `x` = good, `~` = n/a, `-` = concern noted in findings)
```

Keep it concise but readable. Omit empty finding subsections. Target: readable in under 2 minutes.

Copy to clipboard if `pbcopy`/`xclip` available.

## Rules

- NEVER post comments directly on the PR
- ALWAYS read changed files in full context, not just diff hunks
- ALWAYS run tests/build as validation -- don't just read code
- ALWAYS include praise when warranted
- Keep findings terse -- one line each, explain "why" not "what"
- Skip checklist dimensions that don't apply
- No filler, no preamble, no verbose explanations

## Self-Improvement

After execution, use `@skill-improver` to capture observations. Before execution, check `SKILL_NOTES.md` for known edge cases.
