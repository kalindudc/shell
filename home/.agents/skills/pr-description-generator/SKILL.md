---
name: pr-description-generator
description: Generate research-backed PR descriptions that maximize reviewability through structured templates covering purpose, rationale, changes, review guidance, and technical details
---

# PR Description Generator Skill

CRITICAL: before using this skill, load the `cortex` skill — PR descriptions are persisted as cortex tasks, and the persistence/linking steps below assume the cortex CLI vocabulary (`cortex_update`, lanes, tags, statuses).

## Purpose

Generate PR descriptions that maximize reviewability and merge probability through systematic diff analysis and a structured template.

## Brevity Constraint

The entire PR description MUST be readable in under 5 minutes. A description nobody reads helps nobody.

- Prefer bullet points over paragraphs
- One sentence where one sentence suffices — never two
- Omit sections that add no value for a given PR rather than padding them
- If a section can be said in 1 line, say it in 1 line
- The file tree is often the longest section — that is fine, it is scannable

## Process

### 1. Determine the parent branch

- Check whether the GitHub stack extension is available with `command -v gh >/dev/null 2>&1 && gh stack --version >/dev/null 2>&1`
- If available, run `gh stack view --json` to inspect the current stack. NEVER run `gh stack view` without `--json` because it launches an interactive TUI.
- If the current branch is a stack layer, treat `.branches` as bottom-to-top: its parent is the nearest preceding non-merged branch, or `.trunk` for the bottom active layer.
- Capture the current layer's `.base` commit SHA as a candidate diff base. Use it only when `needsRebase` is false and `git merge-base --is-ancestor <base_sha> HEAD` succeeds. If either guard fails, the layer is not linear with its recorded parent; use the parent branch's triple-dot diff and report that the stack needs restacking.
- If `gh stack view --json` reports that the branch is not in a stack, determine whether the user specified a parent branch in the arguments.
- If the parent is still unclear, prompt the user for more information.
- Fetch relevant remote refs before diffing, but do NOT run `gh stack sync` solely to generate a description because it rebases and pushes.

### 2. Gather the related GitHub issue

- Check if a GitHub issue URL or number was provided in `$ARGUMENTS`
- If not provided and the change is self-explanatory from the diff alone (small config/CI changes, docs-only), skip the prompt. Otherwise, prompt the user for a relevant GitHub issue (URL or number).
- For a `github.com` issue URL or number, use `gh issue view <number> --repo <owner>/<repo> --json title,body,labels,state,url` as the primary lookup. Reserve web fetching for non-GitHub issue sources.
- Use the issue to extract context for the Why and Related sections of the PR description

### 3. Get the git diff

- For a linear GitHub stack layer (`needsRebase` is false and `<base_sha>` is an ancestor of `HEAD`), run `git diff <base_sha>..HEAD` as the PRIMARY diff. This captures every commit in that layer; GitHub stacks allow multiple cohesive commits per branch.
- If the stack metadata lacks a usable base SHA or the layer needs rebasing, run `git diff <parent_branch>...HEAD` instead and state the fallback. The triple-dot form uses the merge base and avoids treating a newer, non-ancestor parent tip as part of the layer.
- For non-stacked branches, run `git diff <parent_branch>...HEAD` to get all changes.
- Use the `git_diff_summary` tool for a structured overview of changes with file categorization (source/test/config/docs/migration) and insertion/deletion counts. For a linear stack layer, pass `<base_sha>` as the base. For a triple-dot fallback, compute `git merge-base <parent_branch> HEAD` and pass that merge-base SHA so the summary covers the same layer. This replaces the need to chain `git diff --stat` and `git diff --numstat` manually.
- Run `git log --oneline <base_sha>..HEAD` for a linear stack layer, or `git log --oneline <parent_branch>...HEAD` for a triple-dot fallback or non-stacked branch, to understand the commit narrative. Use commit messages to inform the Summary and Technical Details.

### 4. Analyze the changes

- Review the diff and identify key changes, features, bug fixes, refactoring, etc.
- For PRs dominated by mechanical or auto-generated changes (repetitive renames, derived output from config/template changes), foreground the root-cause change in the Summary and note in Review Guidance that the bulk of the diff is mechanical/derived
- Use the researcher agent for complex analysis if needed
- Discover related plans in cortex (see Cortex persistence below). If exactly one plan plausibly matches the current branch, read its body — the plan's High-Level Objective is often the best source for the Summary's "Why" section. If multiple plausible matches exist, prompt the user. If none match, proceed without a plan reference.
- If the branch has been pushed, check CI status. Note pass/fail in Technical Details if relevant.
- Verify description-code alignment -- ensure every claim matches actual code changes
- If a prior PR-description task already exists for this branch in cortex (same lane, `pr-desc` tag, branch slug in title), prompt the user before generating a new one — stale drafts anchor on outdated claims. Prefer updating the existing task body via `cortex edit --body-file` over creating a duplicate.

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
- **Testing:** [What was tested and how to run it. Omit if the diff contains no source or test files (e.g., docs-only or config-only PRs).]

## Notes for reviewers

[Omit any sub-section below that does not apply. Do NOT pad with filler.]

- **Deploy / migration:** [Only if applicable — deployment steps, flags, rollback]
- **Related:** [Links to issues, tickets, prior PRs]
- **Considerations:** [Backwards compat, perf, known limitations, follow-up planned]
```

## Cortex persistence

PR descriptions live in cortex — not as files. The flow mirrors the `cortex-planner` skill so plans and their PR drafts coexist in the same lane.

1. ALWAYS use the `cortex_update` tool, call that tool for every update. If the tool does not exist follow the Fallback Strategy.
    Fallback strategy: generate ONE session id at the start of your agent session, hold in working memory, and reuse it for the lifetime of the session:
    ```bash
    SESSION_ID="pr-desc-$(openssl rand -hex 4)"   # e.g. pr-desc-7f3a9201
    ```
    Format `<role>-<8 hex>`, max 80 chars, no newlines. NEVER store in env vars (sandboxed sub-shells throw them away) or in repo files (two agents collapse into one identity in the audit trail). The `cortex update <id> --as "$SESSION_ID" -m "..."` examples below are the fallback path — keep using them when the tool is unavailable.

2. LANE = current repository directory name (same as the planner skill):
    ```bash
    LANE=$(git rev-parse --show-toplevel 2>/dev/null | xargs basename || basename "$PWD")
    ```
    Override only when the user explicitly names a different lane.

3. PLAN DISCOVERY. Enumerate plans in the lane and try to match one to the current branch:
    ```bash
    BRANCH=$(git rev-parse --abbrev-ref HEAD)
    cortex ls --lane "$LANE" -t plan --json
    ```
    Match heuristics (in order): branch name contains the plan's stack-slug tag; branch name shares ≥2 slug tokens with the plan title; user explicitly names a plan id in `$ARGUMENTS`. If multiple plans match plausibly, STOP and prompt the user. If none match, proceed without a plan reference.

    Read the matched plan's body to inform the PR description:
    ```bash
    cortex show <plan-id> --json | jq -r .task.body
    ```
    Capture the plan's tags from the same JSON (`.task.tags`) — the PR-desc task MUST inherit them, EXCEPT the `plan` tag (which is reserved for plans themselves).

4. PERSIST THE PR DESCRIPTION. Draft into a tmpfile and persist as a cortex task:
    ```bash
    PR_BODY=$(mktemp -t cortex-pr-desc.XXXXXX.md)
    # write the rendered PR markdown to "$PR_BODY" using the PR Template above

    # Tags: ALWAYS include `pr-desc`. If a related plan was found, ALSO inherit every tag from that
    # plan EXCEPT `plan` itself (that tag is reserved for plans and would mis-classify the PR-desc).
    TAGS="pr-desc"
    if [ -n "$PLAN_ID" ]; then
      PLAN_TAGS=$(cortex show "$PLAN_ID" --json \
        | jq -r '.task.tags | map(select(. != "plan")) | join(",")')
      [ -n "$PLAN_TAGS" ] && TAGS="pr-desc,$PLAN_TAGS"
    fi

    cortex add "PR: <branch_name> - <PR_TITLE>" \
      --lane "$LANE" \
      --priority 1 \
      --status draft \
      --body-file "$PR_BODY" \
      -t "$TAGS"
    ```
    ALWAYS use `--body-file`; NEVER inline `-b "..."` (shell escaping is a footgun for KB-scale markdown).

5. ATTRIBUTE. `cortex add` is anonymous — record WHO drafted the PR description immediately using `cortex_update` tool if available, or the fallback strategy if not:
    Fallback strategy:
    ```bash
    cortex update <pr-id> --as "$SESSION_ID" -m "pr description drafted"
    ```

6. LINK TO THE PLAN (only if a plan was discovered). Post one update on the PR-desc task whose body contains `@<PLAN_ID>` so the cross-reference is recorded in the audit trail using our update strategy from above.
    Use the literal `@<id>` token (no brackets) so it is greppable from `cortex show` output. Skip this step entirely when no plan was matched. For example: `@114`.

7. REVISIONS. To update an existing PR-desc task body, prefer anchor-based edits for surgical changes and `--body-file` for full rewrites — see the `cortex` skill's `cli/edit.md` for tradeoffs. NEVER edit a task whose status is `review` without explicit user confirmation.

## Output Format

- Persist the PR description as a cortex task per the recipe above (lane = repo dir, status = `draft`, tags = `pr-desc` + every tag of the related plan if one exists).
- Inform the user of the cortex task id; the body is viewable via `cortex show <pr-id>`.
- Copy the rendered PR markdown body to clipboard if available (`pbcopy` on macOS, `xclip -selection clipboard` on Linux). Skip if neither is present.
- Max 5 minute read time -- this is non-negotiable

## Template Usage Guidelines

Always include: Summary (with Why and What), Review guidance, Changed files tree, Technical details (non-obvious only).

Include when applicable: Deploy/migration, Related issues/PRs, Screenshots (UI changes only).

Anti-patterns: Empty descriptions, description-code misalignment, generic descriptions ("Fix bug"), missing rationale (WHAT without WHY), over-verbose walls of text.

## Self-Improvement

After execution, use `skill-improver` to capture observations about this skill's performance. Before execution, check `SKILL_NOTES.md` for known edge cases.

## Rules

- ALWAYS load the `cortex` skill first for CLI vocabulary, lane / priority / status / tag semantics, and the `--as` session-id requirement
- ALWAYS persist the PR description via `cortex add --body-file`; NEVER inline `-b "..."` for KB-scale markdown
- ALWAYS attribute the new PR-desc task immediately after `cortex add` with `cortex_update`
- ALWAYS tag the PR-desc task with `pr-desc`; ALSO inherit every tag from the matched plan when a plan was discovered, EXCEPT the reserved `plan` tag
- ALWAYS post a `@<PLAN_ID>` linking update on the PR-desc task when a related plan was matched; SKIP the linking update when no plan was matched
- NEVER create a second PR-desc task for the same branch — update the existing task body instead
- NEVER edit a `review`-status cortex task without explicit user confirmation
- Be thorough in analyzing the changes
- Always format in markdown
- FOLLOW KISS -- if it can be shorter, make it shorter
- NEVER over reference related issues or PRs, if you are unsure if a an issue/PR is relevant, omit it or prompt the user for clarification rather than guessing
- Every claim must match actual code changes -- verify alignment before output
- Omit optional sections entirely rather than filling them with placeholder content
- Brevity is a feature, not a compromise -- say more with less
