---
name: pr-reviewer
description: Multi-model critic consensus PR reviews -- bugs only, false-positive filtered, with structured severity and go/no-go verdicts
# extended: multi-stage pipeline with multi-model critic consensus and embedded evaluation criteria
---

# PR Reviewer Skill

The default review product is a Cortex draft; load or reuse the `cortex` skill when that persistence is within the requested scope. If the user explicitly requests answer-only/no external records, skip Cortex and clipboard writes and return the structured review inline. Do not change an explicitly requested durable product silently; report a persistence blocker if it cannot be delivered.

## Purpose

Review PRs for code health. Output a minimal, actionable review -- not inline PR comments. The user decides what to post. Uses a multi-model critic consensus to aggressively filter false positives before reporting.

Goal: "Would merging this improve the codebase?"

## Process

### Stage 1: Fetch PR context

Use the explicitly provided PR URL/number or pinned source context first. Only when no source was supplied, resolve the current PR with `gh pr view --json number -q .number`; ask once if no unique PR can be identified. Do not check out or detach the user's branch to begin a read-only review.

- Capture metadata with `gh pr view <source> --json title,body,author,baseRefName,baseRefOid,headRefName,headRefOid,files,additions,deletions,url,updatedAt` and retain the reviewed base/head revisions.
- Use the supplied revision-scoped diff or `gh pr diff <source>` as the PR scope. Pair live retrieval with its captured revisions; if references change during retrieval, refresh the affected evidence before relying on it.
- Read relevant source at the pinned revision through authorized read-only tools. If objects are already local, `git show <sha>:<path>` and `git diff <base-sha>...<head-sha>` avoid assuming the active HEAD is the PR head. Missing source is a gap to report, not permission for an automatic checkout/fetch/install workflow.
- Use `git_blame` for material prior-change rationale when that evidence is needed; fetch linked issues only when they affect the review.
- Fetch or reuse applicable PR comments for early deduplication: `gh api repos/{owner}/{repo}/pulls/{number}/comments --jq '.[] | {id, path, line, body}'`. Note incomplete comment coverage instead of claiming exhaustive deduplication.
- Keep API retrieval read-only. If adding query fields with `gh api`, explicitly use `--method GET`; field arguments otherwise change its default method.

### Stage 2: Deep analysis

Read the PR description for intent and use applicable context already supplied. Before reporting a finding, inspect the changed code plus the relevant definitions, callers, data contracts, and tests needed to establish a reachable failure. Expand to full files when those relationships require it; do not explore unrelated code or reread an unchanged snapshot merely because a stage changed. Use registered search/structural tools for unresolved questions.

Focus on BUGS, SECURITY, and LOGIC -- not style or code quality.

Severity tiers:
- Critical: type mismatches causing runtime errors, nil/null crashes, SQL injection, auth/authz bypasses, data corruption/loss, deadlocks, race conditions, memory leaks, unbounded resource usage, breaking API changes
- Medium: N+1 queries degrading performance, missing error handling on critical paths, improper transaction handling, config errors affecting functionality, missing validation on user inputs, incorrect error/status codes
- Minor: bounded concrete behavioral defects or newly introduced public-API documentation errors with a demonstrated misuse path. Missing tests alone are not a finding.

Do NOT report: formatting, naming, style, linter-level issues, theoretical optimizations, "consider using X instead" suggestions. These belong to linters.

If no real issues are found, produce a PASS verdict with empty findings sections. Do NOT invent concerns to populate the template.

Apply the pre-filter below and deduplicate against applicable comments BEFORE delegation. Verify mechanical facts inline; delegate only unresolved substantial investigations, grouped by shared evidence rather than one child per candidate.

Task-array template (fill in actual revisions, paths, and questions):

```json
{"tasks":[{"agent":"researcher","task":"Verify <screened candidate batch> against <pinned diff/source paths> without edits; trace reachable behavior and relevant tests, returning confidence and file:line evidence."}]}
```

Only source-verified inline or delegated findings with CERTAIN or LIKELY confidence proceed. If delegation fails, continue inline only where the evidence is obtainable within scope; report remaining gaps rather than inventing another workflow.

Verification requirements for both paths:
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

An empty screened batch skips this entire stage, including configuration/prompt reads. Otherwise read or reuse `~/.agents/skills/critique/critics.yml` and `critic-prompt.md` once. If configuration, dispatch, or actual identity verification is unavailable, report consensus unavailable/unverified and retain directly supported findings labeled not consensus-filtered. Do not create a probe or substitute-review loop to claim diversity.

1. Send the screened finding batch in one `spawn` tasks array with one task per configured critic model, explicitly setting each model. Include finding IDs/evidence, the shared prompt and criteria, relevant diff/source snapshots, and a bounded read-only scope. Require KEEP/REJECT/ABSTAIN with rationale per finding; split only for a demonstrated context limit.
2. With N configured critics, multi-model validation requires KEEP from `max(2, floor(N / 2) + 1)` distinct, verified actual model identities, one vote per model. Requested labels and model self-reports do not verify dispatch.
3. Abstentions, duplicate identities, timeouts, missing verification, and tool failures never lower the quorum. Below-quorum findings remain explicitly not consensus-filtered, not silently discarded or labeled validated.
4. Inspect specific conflicts between votes and source evidence and report unresolved disagreement instead of rerunning until favorable votes appear. Agreement is not factual proof. Refresh only evidence invalidated by relevant changes, missing context, or material freshness needs.

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

Use the comment snapshot already screened before delegation to make the final deduplication decision. Re-fetch only when relevant comments changed or current coverage is materially required, not simply because this stage was reached.

A finding is a DUPLICATE if:
- Same issue already raised by any commenter (even if worded differently)
- Same file, overlapping lines (within 5 lines), same problem
- An existing comment covers a parent/child of the same issue

When uncertain, mark as duplicate. Better to skip a duplicate than repeat one.

### Stage 5: Output

Use applicable revision-scoped CI/local evidence first. Run only relevant, authorized validation that addresses a concrete uncertainty, after inspecting the command and its side effects. Do not execute a blanket build/test/lint cycle or a modifying formatter merely to complete a review stage. Record each performed command and outcome; label unperformed validation and blockers explicitly.

If execution requires a checkout/worktree, obtain authorization when not already supplied and protect the user's dirty worktree. A disposable worktree isolates file changes, not network access or credentials; it is not a security sandbox. If the required scope/environment is unavailable, continue only with permitted static inspection and report limitations—no unapproved installs, destructive cleanup, or claims that tests passed.

For Terraform workspaces: `terraform validate` confirms schema conformance but does NOT validate semantic correctness of attribute interactions. Cross-reference provider documentation for resource types in the diff to verify behavioral intent matches configuration.

Verdict system:
- PASS: No substantiated significant issues in the reviewed scope; this does not certify unperformed validation or guarantee merge safety.
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

Omit empty finding subsections (except for PASS with no findings). Clearly distinguish consensus-filtered findings from directly verified findings whose consensus was unavailable/below quorum. Use the Cortex persistence section for the configured durable product unless the user explicitly requested answer-only/no external records; that mode returns the review inline without Cortex or clipboard writes.

## Cortex persistence

When durable output is authorized, PR reviews live in Cortex—not substitute files—and coexist with plans and PR descriptions in the same lane. Skip this entire section for an explicit answer-only/no-external-records request. If requested persistence is unavailable, report that blocker without claiming it succeeded or creating an alternate artifact.

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

- For authorized durable output, persist the review per the recipe above (repo lane, `draft`, `pr-review` plus supplied-plan tags except reserved `plan`); leave priority unset unless explicitly requested.
- Report the created task ID only after persistence succeeds; its body is viewable via `cortex show <review-id>`. For explicit answer-only mode, return the structured review inline instead.
- Copy to clipboard only within the requested output scope and when the capability is available.

## Self-Improvement

Capture feedback only for concrete, novel, reusable evidence from this task and within its authorized scope. Ordinary success or restating existing guidance starts no notes read, observer, or promotion.

When capture is justified, the current agent owns the gate: resolve `SKIP_SKILL_NOTES` from the environment only (never `.env`); `1` or `true` disables notes. Otherwise use the `improve-skills` Fast Loop. Reuse applicable evidence; one owner and at most one entry per skill/session. A delegated observer receives `notes_enabled=true`, the target, and the concrete observation.

## Rules

Cortex-specific rules below apply to authorized durable output, not explicit answer-only mode.

- Load or reuse the `cortex` skill when persistence is required; preserve its attribution/status semantics.
- Persist authorized durable reviews via `cortex add --body-file`; NEVER inline `-b "..."` for KB-scale markdown.
- ALWAYS attribute the new review task immediately after `cortex add` with `cortex_update` (include the verdict in the message)
- ALWAYS tag the review task with `pr-review`; ALSO inherit every tag from the user-specified plan when one was provided, EXCEPT the reserved `plan` tag
- NEVER auto-discover plans for reviews — only link to a plan when the user explicitly names a plan id in `$ARGUMENTS`
- ALWAYS post a `@<PLAN_ID>` linking update on the review task when the user supplied a plan id; SKIP the linking update otherwise
- NEVER edit a `review`-status cortex task without explicit user confirmation
- NEVER post comments directly on the PR
- NEVER report style, formatting, or theoretical concerns -- bugs only
- Verify findings against relevant source context, callers/contracts, and tests; expand reads when needed, not merely to satisfy a stage.
- Use relevant authorized validation or still-applicable evidence; explicitly report unperformed checks and blockers. Never infer test success from missing counts or an unverified claim.
- Label multi-model validation only when the fixed distinct-model quorum is met; preserve directly supported issues with an honest degraded/unfiltered label when consensus is unavailable.
- If no real issues found, output PASS with empty sections
- Keep findings terse -- one line each, explain "why" not "what"
- Skip checklist dimensions that don't apply
- No filler, no preamble, no verbose explanations
