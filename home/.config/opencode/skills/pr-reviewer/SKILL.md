---
name: pr-reviewer
description: Perform structured, research-backed PR reviews with categorized findings, severity labels, and actionable feedback
---

# PR Reviewer Skill

## Purpose

Perform thorough PR reviews that go beyond bug-finding to evaluate design, complexity, tests, and code health.

The reviewer's goal: "Would approving this PR improve the overall code health of the system?"

Output is a structured review summary -- not inline PR comments. The user decides what to post.

## Process

### 1. Fetch PR context

The command's pre-requisites already resolved the PR and checked out the remote branch.

- Use `gh pr view <number> --json title,body,author,baseRefName,headRefName,files,additions,deletions,url` for metadata
- Use `gh pr diff <number>` for the full diff
- Use `git_diff_summary` for structured file categorization (replaces chaining `git diff --stat` and `--numstat`)
- Use `git_blame_context` on critical changed regions to understand ownership and prior change rationale
- If the PR description is thin or missing, note it as a finding.

### 2. Understand the change

The #1 review activity is understanding.

- Read the PR description to understand intent and context
- Read changed files in full context (not just diff hunks) -- use Read tool
- Use `ast_query` to understand structural patterns the PR touches (e.g., class hierarchies, function signatures)
- If the codebase is unfamiliar, use `@codebase-explorer` to map the architecture around the changed files before evaluating design
- If the PR references an issue, fetch it via `gh issue view`
- Identify: what problem is being solved, what approach was taken, what alternatives exist

### 3. Review using structured checklist

Evaluate each dimension (skip dimensions that don't apply):

- **Design**: Does the change belong here? Does it integrate well?
- **Functionality**: Does it do what the author intended? Edge cases?
- **Complexity**: Can it be understood quickly? Over-engineering?
- **Tests**: Appropriate coverage? Tests correct and useful? Run all tests and check for failures (read repo guidelines for test execution)
- **Naming**: Clear, descriptive, not too long?
- **Comments**: Explain "why" not "what"? Necessary?
- **Style & Consistency**: Follows project conventions?
- **Documentation**: Updated if user-facing behavior changed?

### 4. Categorize and label findings

Each finding gets a severity label:

- **Blocker**: Must fix before merge (bugs, security, data loss)
- **Concern**: Should fix, significant quality impact
- **Suggestion**: Would improve code but not blocking
- **Nit**: Minor style/preference, take it or leave it
- **Praise**: Something done well -- tell developers what they did right

Each finding includes: file:line reference (where applicable), brief explanation of **why** (not just what).

## Output

Write the structured review to `./tmp/pr-review/<pr-number>-review.md`:

```markdown
# PR Review: #<number> - <title>

**Author:** <author> | **Base:** <base> -> <head>
**Verdict:** Approve / Request Changes / Comment

## Summary
[1-3 sentences: what the PR does, overall assessment]

## Findings

### Blockers
- [Blocker] file:line -- description

### Concerns
- [Concern] file:line -- description

### Suggestions
- [Suggestion] file:line -- description

### Nits
- [Nit] file:line -- description

### Praise
- [Praise] file:line -- description

## Checklist
- [x/~/-] Design
- [x/~/-] Functionality
- [x/~/-] Tests
...etc (only checked dimensions)
```

Target: review readable in under 5 minutes. Omit empty severity sections.
Copy to clipboard if `pbcopy`/`xclip` available.

## Self-Improvement

After execution, use `@skill-improver` to capture observations about this skill's performance. Before execution, check `SKILL_NOTES.md` for known edge cases.

## Rules

- NEVER post comments directly on the PR -- output the review for the user to act on
- ALWAYS read changed files in full context, not just diff hunks
- ALWAYS label finding severity explicitly
- ALWAYS explain "why" for each finding, not just "what"
- ALWAYS include praise when warranted -- reviews are not just about mistakes
- NEVER block on personal style preferences -- use "Nit:" label
- FOLLOW KISS -- skip checklist dimensions that don't apply to the PR
