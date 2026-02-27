---
name: pr-description-generator
description: Generate research-backed PR descriptions that maximize reviewability through structured templates covering purpose, rationale, changes, review guidance, and technical details
---

# PR Description Generator Skill

## Purpose

Generate PR descriptions that maximize reviewability and merge probability through systematic diff analysis and a structured template.

## Brevity Constraint

**The entire PR description MUST be readable in under 5 minutes. A description nobody reads helps nobody.**

- Prefer bullet points over paragraphs
- One sentence where one sentence suffices — never two
- Omit sections that add no value for a given PR rather than padding them
- If a section can be said in 1 line, say it in 1 line
- The file tree is often the longest section — that is fine, it is scannable

## Process

### 1. Determine the parent branch

- Check if graphite CLI is available by running `which gt`
- If available, run `gt log` to determine the parent branch from the stack
- If not available, determine if the user specified a parent branch in the arguments
- If unclear, prompt the user for more information on the parent branch

### 2. Gather the related GitHub issue

- Check if a GitHub issue URL or number was provided in `$ARGUMENTS`
- If not provided, **prompt the user** for a relevant GitHub issue (URL or number)
- Use the issue to extract context for the **Why** and **Related** sections of the PR description

### 3. Get the git diff

- Run `git diff <parent_branch>...HEAD` to get all changes
- Run `git diff --stat <parent_branch>...HEAD` for a file change summary
- Run `git log --oneline <parent_branch>...HEAD` to understand the commit narrative. Use commit messages to inform the Summary and Technical Details.

### 4. Analyze the changes

- Review the diff and identify key changes, features, bug fixes, refactoring, etc.
- Spawn subagents if needed for complex analysis
- If a plan file exists in `./tmp/plan/`, read it to understand the intent behind the changes. The plan's High-Level Objective is often the best source for the Summary's "Why" section.
- If the branch has been pushed, check CI status. Note pass/fail in Technical Details if relevant.
- **Verify description-code alignment** -- ensure every claim matches actual code changes

### 5. Generate the PR description using the template below

## PR Template

Structured by impact on review outcomes (highest-impact elements first). Keep it tight.

```markdown
## Summary

[Imperative one-liner — "Add X", "Fix Y", "Refactor Z". Must stand alone in git history.]

**Why:** [1-2 sentences. What problem does this solve? What breaks without it?]

**What:** [Bullet list of key changes — keep to 3-5 bullets max]

## Review guidance

[2-4 bullets: what to focus on, areas of uncertainty, what kind of feedback you want]

## Changed files

**CRITICAL REQUIREMENT**: The file tree should only display the changed files in a tree format WITHOUT any other details, the tree display should only contain information of the actual files that were changed.

[changed files as a tree]

File tree format:
\```
foo/bar/
├── src/
│   ├── modules/
│   │   ├── foo.rs                           (+100 -10)
│   │   └── tests/
│   │       └── foo.rs                       (+1,000 -100)
│   └── tests.textpb                         (+0 -200)
├── config/
│   └── config.json                          (+200 -10)
└── docs/                                    (new)
    └── README.md                            (+500 -10)

5 files changed: 1,800 insertions, 330 deletions
\```

## Technical details

[Keep this section concise. Cover implementation decisions, edge cases, and testing — but only what a reviewer needs to know. Skip obvious things.]

- **Implementation:** [Key decisions and approach — not a line-by-line walkthrough]
- **Edge cases:** [What tricky scenarios are handled]
- **Testing:** [What was tested and how to run it]

## Notes for reviewers

[Omit any sub-section below that does not apply. Do NOT pad with filler.]

- **Deploy / migration:** [Only if applicable — deployment steps, flags, rollback]
- **Related:** [Links to issues, tickets, prior PRs]
- **Considerations:** [Backwards compat, perf, known limitations, follow-up planned]
```

## Output Format

- Output the final PR description to `./tmp/pr/<branch_name>-pr.md`
- Copy to clipboard if available (`pbcopy` on macOS, `xclip -selection clipboard` on Linux). Skip if neither is present.
- **Max 5 minute read time — this is non-negotiable**

## Template Usage Guidelines

**Always include:** Summary (with Why and What), Review guidance, Changed files tree, Technical details (non-obvious only).

**Include when applicable:** Deploy/migration, Related issues/PRs, Screenshots (UI changes only).

**Anti-patterns:** Empty descriptions, description-code misalignment, generic descriptions ("Fix bug"), missing rationale (WHAT without WHY), over-verbose walls of text.

## Rules

- Be thorough in analyzing the changes
- Always format in markdown
- FOLLOW KISS -- if it can be shorter, make it shorter
- NEVER over reference related issues or PRs, if you are unsure if a an issue/PR is relevant, omit it or prompt the user for clarification rather than guessing
- **Every claim must match actual code changes** -- verify alignment before output
- Omit optional sections entirely rather than filling them with placeholder content
- **Brevity is a feature, not a compromise** -- say more with less
