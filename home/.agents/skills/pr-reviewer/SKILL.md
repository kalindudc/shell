---
name: pr-reviewer
description: Multi-model critic consensus PR reviews -- bugs only, false-positive filtered, with structured severity and go/no-go verdicts
# extended: multi-stage pipeline with multi-model critic consensus and embedded evaluation criteria
---

# PR Reviewer Skill

CRITICAL: before using this skill, load the `cortex` skill — PR reviews are persisted as cortex tasks, and the persistence/linking steps below assume the cortex CLI vocabulary (`cortex_update`, lanes, tags, statuses).

## Purpose

Review PRs for code health. Output a minimal, actionable review -- not inline PR comments. The user decides what to post. Uses a multi-model critic consensus to aggressively filter false positives before reporting.

Goal: "Would merging this improve the codebase?"

## Process

### Stage 1: Fetch PR context

Pre-requisites already resolved the PR and checked out the remote branch. If `gh pr checkout` fails (deleted branch), use `gh pr view --json headRefOid` + `git checkout <sha> --detach`.

- `gh pr view <number> --json title,body,author,baseRefName,headRefName,files,additions,deletions,url`
- `gh pr diff <number>` -- the authoritative diff source. Prefer over `git-diff-summary` for scope (it can include merged-in changes on diverged branches).
- For merged-main branches: use three-dot diff (`git diff base...HEAD`) and `gh pr view --json commits` to disambiguate PR-specific changes from merged-in noise
- `git_blame_context` on critical changed regions for prior change rationale
- If PR references an issue, fetch via `gh issue view`
- Fetch existing PR comments for dedup: `gh api repos/{owner}/{repo}/pulls/{number}/comments --jq '.[] | {id, path, line, body}'`

### Stage 2: Deep analysis

Read PR description for intent. When the description is thorough with structured sections, leverage it to skip exploratory investigation and focus on validating claims against the diff. Read changed files in full context (not just diff hunks). Use `ast_query` for structural patterns if needed. Use available search tools (grep, find, ast_query) to explore unfamiliar areas of the codebase.

Focus on BUGS, SECURITY, and LOGIC -- not style or code quality.

Severity tiers:
- Critical: type mismatches causing runtime errors, nil/null crashes, SQL injection, auth/authz bypasses, data corruption/loss, deadlocks, race conditions, memory leaks, unbounded resource usage, breaking API changes
- Medium: N+1 queries degrading performance, missing error handling on critical paths, improper transaction handling, config errors affecting functionality, missing validation on user inputs, incorrect error/status codes
- Minor: missing tests for NEW functionality that could mask bugs, documentation gaps that could cause misuse of a public API

Do NOT report: formatting, naming, style, linter-level issues, theoretical optimizations, "consider using X instead" suggestions. These belong to linters.

If no real issues are found, produce a PASS verdict with empty findings sections. Do NOT invent concerns to populate the template.

For each potential finding, invoke the researcher agent for deep investigation:
  spawn(agent: "researcher", task: "<potential finding + diff path + worktree path>")

The researcher investigates (call-stack tracing, test coverage checks, language
verification, line number verification) and returns findings with confidence levels
and verbatim evidence.

Only findings returned with CERTAIN or LIKELY confidence proceed to Stage 3.

If the researcher fails or times out, fall back to inline verification:
1. VERIFY the language -- confirm syntax, stdlib, and library behavior
2. TRACE the call stack -- check if upstream callers prevent or downstream handles it
3. CHECK test coverage -- search for existing tests covering this scenario
4. VERIFY line numbers -- read the source file, confirm code matches. Only reference lines CHANGED in the PR. If bug is in unchanged code, omit line numbers.

Impact per finding (1-2 sentences): who is affected (users, services) and what happens (corruption, outage, incorrect behavior)?

Pre-filter (reduce critic workload by catching obvious false positives early):
- Do NOT flag missing nil checks without a concrete reachable failure path
- Do NOT flag PR changes as regressions without evidence they are unintended
- Respect encapsulation (don't re-litigate what the called method owns)
- Require EVIDENCE before flagging failure paths -- "could plausibly fail" is not sufficient
- Match standards to context (rake tasks, CLI tools, test fixtures != production code)

Scan for hidden artifacts: whitespace/alignment hunks hiding unrelated additions, AI-injected URL tracking params (`?utm_source=openai`), dead code introduced via conflict resolution.

For infrastructure-as-code (Terraform, Pulumi, CloudFormation) and unfamiliar library/provider APIs:
- Fetch provider/library documentation for every resource type or API being configured. For Terraform, fetch docs from provider GitHub repos (raw content), not registry.terraform.io (requires JS). Cross-reference `.terraform.lock.hcl` for the locked provider version and fetch docs for that version tag, not latest.
- Verify that attribute combinations are semantically valid (not just syntactically accepted)
- Trace default values to their runtime behavior: "what happens if a caller relies on this default?"

Self-review: If the reviewer is also the PR author, note the conflict in the Summary and adjust focus toward objective structural concerns rather than subjective design choices. For IaC repos without test suites, the Tests checklist dimension defaults to `[~] N/A`.

### Stage 3: Multi-model critic consensus

If the critique infrastructure is unavailable (critics.yml missing or unreadable), retain all findings that passed researcher verification with CERTAIN or LIKELY confidence. Note in the output: "Consensus step skipped -- findings retained based on researcher verification only. N findings would normally be filtered by consensus." Skip to Stage 4.

Invoke multi-model critic consensus using the critique infrastructure:

1. Read `~/.agents/skills/critique/critics.yml` to get the available critic models
2. Read `~/.agents/skills/critique/critic-prompt.md` to get the shared evaluation prompt
3. For each finding, construct a `spawn` call with `tasks` array -- one task per critic model.
   Each task's `task` field = the critic prompt + finding details + evaluation criteria below + PR diff context.
   Each task's `model` field = the model identifier from critics.yml.
4. Collect results, extract KEEP/REJECT/ABSTAIN votes from each critic's response
5. Apply dynamic consensus: majority KEEP = finding survives. Adjust threshold when critics abstain/timeout (e.g., 2/3 KEEP when one critic abstains).

Each critic receives: the finding (severity, file:line, title, description, suggestion),
the PR diff (or relevant excerpts for large diffs), and the worktree path for code exploration.

#### Evaluation Criteria

REJECT if any of these apply:
- Style, formatting, linting, or naming issue
- Testing suggestion (unless a test doesn't test what it claims)
- Best practice or maintainability concern without behavior change
- Theoretical optimization or speculative concern without evidence
- Scope creep (redesign beyond the PR)
- Hallucinated standard or API behavior
- Pre-existing issue not introduced by this PR
- Missing nil/null check with no reachable failure path
- Intentional design decision (the PR clearly intends the change)
- Encapsulation re-litigation (called method already handles it)
- Production standard applied to scripts, CLI tools, or test fixtures

KEEP only if ALL true:
- REAL bug, security vuln, or logic contradiction
- INTRODUCED by this PR (in added/modified lines)
- CONCRETE, PROVABLE, IMMEDIATE impact
- Verified by reading the actual code

Note in the output summary how many critic sessions were spawned and total findings
evaluated for cost transparency.

### Stage 4: Deduplication

Compare surviving findings against existing PR comments fetched in Stage 1.

A finding is a DUPLICATE if:
- Same issue already raised by any commenter (even if worded differently)
- Same file, overlapping lines (within 5 lines), same problem
- An existing comment covers a parent/child of the same issue

When uncertain, mark as duplicate. Better to skip a duplicate than repeat one.

### Stage 5: Output

Run the project's test suite and any relevant build/lint commands. Read repo guidelines for test execution. Record each command and its outcome.

For Terraform workspaces: `terraform validate` confirms schema conformance but does NOT validate semantic correctness of attribute interactions. Cross-reference provider documentation for resource types in the diff to verify behavioral intent matches configuration.

Verdict system:
- PASS: No significant issues. Safe to merge.
- GO WITH FIXES: Minor issues, not blocking.
- NEEDS REVIEW: Moderate issues needing human attention before merge.
- BLOCK: Critical bugs. Do NOT merge until fixed.

Render the review using this template:

```markdown
# PR #<number> - <title>

Author: <author> | <base> -> <head>
Verdict: PASS / GO WITH FIXES / NEEDS REVIEW / BLOCK

## Summary
<2-3 sentences: what the PR does, severity breakdown, critic consensus stats>
e.g., "2 critical, 1 medium findings survived critic review (5 of 8 initial findings filtered). 3 critic sessions spawned."

## Findings

### Critical
- `file:line` -- **Title**: description with evidence and code snippets.
  Impact: <concrete impact>. Suggestion: <fix>.
  Critic consensus: <votes>/<critics> KEEP

### Medium
- ...

### Minor
- ...

### Praise
- `file:line` -- description

### Filtered (for reference)
<N> findings filtered by critic consensus:
- `file:line` -- <title> (votes: <votes>/<critics> KEEP -- <primary rejection reason>)

## Validation
- `<command>` -- <result>

## Checklist
- [x] Design  ...

(only dimensions evaluated: x = good, ~ = n/a, - = concern noted in findings)
```

Omit empty finding subsections (except for PASS verdict where all sections are empty by design). Persist this rendered markdown via the Cortex persistence section below. Copy the body to clipboard if `pbcopy`/`xclip` available.

## Cortex persistence

PR reviews live in cortex — not as files. The flow mirrors the `pr-description-generator` skill so reviews coexist with plans and PR descriptions in the same lane.

1. ALWAYS use the `cortex_update` tool, call that tool for every update. If the tool does not exist follow the Fallback Strategy.
    Fallback strategy: generate ONE session id at the start of your agent session, hold in working memory, and reuse it for the lifetime of the session:
    ```bash
    SESSION_ID="pr-review-$(openssl rand -hex 4)"   # e.g. pr-review-7f3a9201
    ```
    Format `<role>-<8 hex>`, max 80 chars, no newlines. NEVER store in env vars (sandboxed sub-shells throw them away) or in repo files (two agents collapse into one identity in the audit trail). The `cortex update <id> --as "$SESSION_ID" -m "..."` examples below are the fallback path — keep using them when the tool is unavailable.

2. LANE = current repository directory name (same as the planner and pr-desc skills):
    ```bash
    LANE=$(git rev-parse --show-toplevel 2>/dev/null | xargs basename || basename "$PWD")
    ```
    Override only when the user explicitly names a different lane.

3. PLAN LINKING (USER-SPECIFIED ONLY). Do NOT auto-discover plans for reviews. Inspect `$ARGUMENTS` for an explicit plan reference — patterns like `plan #42`, `--plan 42`, `for plan 42`, or a bare `#42` token paired with the word `plan`. Extract the integer id into `PLAN_ID`. If the user did not specify a plan, leave `PLAN_ID` empty and skip every plan-related step below.

    If a `PLAN_ID` was supplied, validate it and capture its tags (so the review task can inherit them, EXCEPT the reserved `plan` tag):
    ```bash
    cortex show "$PLAN_ID" --json | jq -r .task.title    # confirm it exists; abort if not
    ```

4. PERSIST THE PR REVIEW. Draft the rendered review markdown into a tmpfile and persist as a cortex task:
    ```bash
    REVIEW_BODY=$(mktemp -t cortex-pr-review.XXXXXX.md)
    # write the rendered review markdown to "$REVIEW_BODY" using the template above

    # Tags: ALWAYS include `pr-review`. If the user named a plan, ALSO inherit every tag from that
    # plan EXCEPT `plan` itself (that tag is reserved for plans and would mis-classify the review).
    TAGS="pr-review"
    if [ -n "$PLAN_ID" ]; then
      PLAN_TAGS=$(cortex show "$PLAN_ID" --json \
        | jq -r '.task.tags | map(select(. != "plan")) | join(",")')
      [ -n "$PLAN_TAGS" ] && TAGS="pr-review,$PLAN_TAGS"
    fi

    cortex add "PR Review #<pr-number>: <pr-title>" \
      --lane "$LANE" \
      --priority 1 \
      --status draft \
      --body-file "$REVIEW_BODY" \
      -t "$TAGS"
    ```
    ALWAYS use `--body-file`; NEVER inline `-b "..."` (shell escaping is a footgun for KB-scale markdown).

5. ATTRIBUTE. `cortex add` is anonymous — record WHO drafted the review immediately using the `cortex_update` tool if available, or the fallback strategy if not:
    Fallback strategy:
    ```bash
    cortex update <review-id> --as "$SESSION_ID" -m "pr review drafted: <verdict>"
    ```
    Include the verdict (PASS / GO WITH FIXES / NEEDS REVIEW / BLOCK) in the message so it surfaces in `cortex ls`.

6. LINK TO THE PLAN (only if the user supplied a plan id). Post one update on the review task whose body contains `@<PLAN_ID>` so the cross-reference is recorded in the audit trail using our update strategy from above.
    Use the literal `@<id>` token (no brackets) so it is greppable from `cortex show` output. Skip this step entirely when no plan was specified. For example: `@114`.

7. REVISIONS. To update an existing review task body, prefer anchor-based edits for surgical changes and `--body-file` for full rewrites — see the `cortex` skill's `cli/edit.md` for tradeoffs. NEVER edit a task whose status is `review` without explicit user confirmation.

## Output Format

- Persist the rendered review as a cortex task per the recipe above (lane = repo dir, status = `draft`, tags = `pr-review` + every tag of the user-specified plan if one was provided, EXCEPT the reserved `plan` tag).
- Inform the user of the cortex task id; the body is viewable via `cortex show <review-id>`.
- Copy the rendered review markdown body to clipboard if available (`pbcopy` on macOS, `xclip -selection clipboard` on Linux). Skip if neither is present.

## Self-Improvement

After execution, use `skill-improver` to capture observations. Before execution, check `SKILL_NOTES.md` for known edge cases.

## Rules

- ALWAYS load the `cortex` skill first for CLI vocabulary, lane / priority / status / tag semantics, and the `--as` session-id requirement
- ALWAYS persist the PR review via `cortex add --body-file`; NEVER inline `-b "..."` for KB-scale markdown
- ALWAYS attribute the new review task immediately after `cortex add` with `cortex_update` (include the verdict in the message)
- ALWAYS tag the review task with `pr-review`; ALSO inherit every tag from the user-specified plan when one was provided, EXCEPT the reserved `plan` tag
- NEVER auto-discover plans for reviews — only link to a plan when the user explicitly names a plan id in `$ARGUMENTS`
- ALWAYS post a `@<PLAN_ID>` linking update on the review task when the user supplied a plan id; SKIP the linking update otherwise
- NEVER edit a `review`-status cortex task without explicit user confirmation
- NEVER post comments directly on the PR
- NEVER report style, formatting, or theoretical concerns -- bugs only
- ALWAYS read changed files in full context, not just diff hunks
- ALWAYS run tests/build as validation
- No finding survives without majority critic votes
- If no real issues found, output PASS with empty sections
- Keep findings terse -- one line each, explain "why" not "what"
- Skip checklist dimensions that don't apply
- No filler, no preamble, no verbose explanations
