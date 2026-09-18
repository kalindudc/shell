---
name: pr-reviewer
description: Multi-model critic consensus reviews -- bugs only, false-positive filtered, with structured severity and go/no-go verdicts. Targets GitHub PRs or local WIP/branch reviews via tuicr annotation sessions with a cortex findings ledger
# extended: multi-stage pipeline with multi-model critic consensus and embedded evaluation criteria
---

# PR Reviewer Skill

The default review product is a Cortex draft; load or reuse the `cortex` skill when that persistence is within the requested scope. If the user explicitly requests answer-only/no external records, skip Cortex and clipboard writes and return the structured review inline. Do not change an explicitly requested durable product silently; report a persistence blocker if it cannot be delivered.

## Purpose

Review PRs for code health. Output a minimal, actionable review -- not inline PR comments. The user decides what to post. Uses a multi-model critic consensus to aggressively filter false positives before reporting.

Goal: "Would merging this improve the codebase?"

Two targets: GitHub PRs (default flow below) and local WIP/branch reviews (see `Local review sessions with tuicr`). Both persist to the same cortex review task.

## Process

### Stage 1: Fetch PR context

MODE FORK: if the review target is LOCAL work (WIP, uncommitted changes, or a feature branch, with no PR source), skip this stage's `gh` retrieval and follow `Local review sessions with tuicr` below for scope and session mint; stages 2-4 apply with 'the PR' meaning the review-scope diff, and intent comes from the user's request, branch name, and commit messages instead of a PR description.

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

LOCAL MODE: there is no PR comment snapshot. Deduplicate against the cortex findings ledger from prior rounds: a candidate matching an existing `open`/carried finding (same essence -- category + offending code pattern, never line numbers) IS that finding -- re-anchor and continue it under its F-id instead of creating a new one. A candidate matching a `fixed`/`wontfix` entry is a regression or repeat -- name its F-id explicitly instead of minting a fresh finding.

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

## Local review sessions with tuicr

MODE TRIGGER: the user asks to review local work -- WIP, uncommitted changes, or a feature branch -- with no PR source. Stages 2-4 (deep analysis, critic consensus, deduplication) run unchanged against the local diff; Stage 1 and Stage 5 fork as below.

Architecture: tuicr is ONLY the live annotation transport between agent and human. The cortex review task is the durable ledger and the ONLY memory across rounds. Tuicr sessions are disposable, HEAD-pinned views -- never read old sessions for context, never mutate them.

Load the `tuicr` skill for all session mechanics (discovery, launch, headless mint, comment semantics, diff reconstruction). This section defines only the review protocol layered on top. A pr-reviewer local review IS the tuicr skill's 'agent review' workflow with pre-authorized comment writing -- do not re-ask for approval to annotate the session you minted.

### Stage 1 (local): scope and session mint

1. Scope: resolve `<base>` (user-named ref, else the merge-base with the default branch). Review diff = `git diff <base>..HEAD` PLUS uncommitted worktree changes. Pin `HEAD_SHA=$(git rev-parse --short HEAD)` -- every round binds to its HEAD. UNTRACKED files are invisible to `git diff` scopes: `git add -N` new files that must be reviewable under `-r` scopes (`-w` covers them), and treat the session's `file_count` as the ground truth for what is annotatable.
2. Mint per the `tuicr` skill's `Start A Session` (wrapper when a multiplexer is available, else the headless mint). Scope flags by HEAD position: when `<base>` resolves to HEAD itself (the canonical WIP-on-default-branch case) pass `-w` ALONE -- `-r HEAD..HEAD -w` exits 1 "No changes to review" despite a dirty worktree (verified 0.26.0); otherwise pass `-r <base>..HEAD -w`. An empty diff mints NOTHING. Bind only a FRESH slug (absent from the pre-mint listing) -- never annotate a stale session, never reuse a session across different HEADs.

### Stage 5 (local): annotate findings in tuicr

One `tuicr review add` per finding (no batch mode), following the `tuicr` skill's `Add Agent Comments` mechanics, including its verify-after-add step (a line outside the diff exits 0 but never renders). Every agent comment carries a STABLE finding id that never changes across rounds:

- Id + severity prefix in every comment: `[F3] medium: divide-by-zero if compute() returns 0` -- terse "why", plain language. Comment usefulness depends on comprehensibility and politeness as much as technical content, and high comment volume reduces usefulness (Ram et al., EMSE 2023) -- fewer, better comments.
- Anchor at the CURRENT line per the tuicr skill's side/range rules; only files in the session's diff are annotatable (`session does not contain file` otherwise) -- fall back to a review-level comment (omit `--target-file`) for anything else.
- Pass `--username "agent:<session-id>"` so human vs agent authorship is separable when harvesting.
- NEVER `:submit`/export to a forge -- annotations stay `local_draft`; tuicr is a local transport only.

### Validate the review before handoff

Before flipping the task to `review`, mechanically validate the review itself:

1. CONSISTENCY: every annotation's `[F<id>]` in the session exists in the ledger, and every ledger `open` finding has exactly one annotation in the current session. Diff the id sets (`tuicr review comments --session <slug>` vs the ledger table) and fix mismatches BEFORE handoff -- a finding that lives in only one of the two stores breaks the next round.
2. EVIDENCE: every finding carries its verification (command run, file:line read, or trace) in the review body; findings without concrete evidence are downgraded or dropped -- "could plausibly fail" never ships.
3. COVERAGE: state files-in-diff vs files-examined (the session's `file_count` vs your analysis); name every file NOT examined and why. A review that silently skips half the diff is worse than no review.
4. ANCHORS: re-run the tuicr skill's verify-after-add for every line comment (a line outside the diff exits 0 but never renders).

For high-stakes or contested reviews, optionally run an adversarial meta-review BEFORE annotating tuicr: dispatch the assembled review body + findings through the Stage 3 critic mechanics with KEEP/REJECT per finding, and record in the body whether it ran. The human side of validation is the tuicr session itself (confirm/reject per finding, harvested next round); the ledger's wontfix/fixed history over rounds is the review's empirical false-positive rate -- feed it to the Self-Improvement loop.

The cortex body for local mode = the standard review template (verdict, findings, validation) PLUS the findings ledger and round log below.

### The cortex findings ledger

Every annotation is mirrored in the review task body. Design borrows the converged industry model (SARIF, Gerrit, Semgrep, SonarQube): IDENTITY is location-independent; LOCATION is per-round; ONE canonical finding per issue; per-round annotations are views of it.

```markdown
## Findings ledger

| id | severity | status | first seen | latest location | summary (why, one line) |
|----|----------|--------|------------|-----------------|-------------------------|
| F1 | critical | fixed  | r1 @8a04250 | src.rs:13 (r1) | divide-by-zero if compute() returns 0 |

## Round log

- r1 @8a04250 (`<slug>`): 3 findings F1-F3, verdict NEEDS REVIEW
- r2 @7b08b13 (`<slug>`): F1 fixed in 7b08b13; F2 carried (re-validated, re-anchored src.rs:20); F3 wontfix (human: "intentional"); F4 new
```

Ledger rules grounded in prior art:

- Statuses: `open | fixed | outdated | wontfix` (Semgrep/GitHub). `carried` is a per-round projection, never stored -- like Gerrit ported comments ("not copies"), a carried annotation is the SAME finding rendered at a new location.
- Matching across rounds: match on the issue's ESSENCE -- category + the offending code pattern -- NEVER on line numbers (SARIF fingerprints: identity must be "resistant to changes... such as the line number").
- Porting rule (Gerrit): carry ONLY `open` findings into a new round; recompute the anchor; degrade line -> file-level -> review-level (dropped from tuicr but kept in the ledger). `fixed`/`wontfix` are never carried -- they stay readable in their original session.

### Review rounds (after new commits)

1. START: the user signals fixes are in. That signal is explicit confirmation to flip the cortex task `review` -> `open` and edit the ledger. Read the task body -- the ledger is the ONLY prior context needed; do NOT re-read old tuicr sessions (archives).
2. HARVEST the last session (`tuicr review comments --session <slug>`): comments whose author is not `agent:*` are human input -- map `[F<id>]` mentions to ledger entries (update status, e.g. wontfix with the human's rationale) or add human-raised items as new findings (next free id, severity from your own analysis).
3. RE-VALIDATE every `open`/carried finding against the NEW code as a full re-check (fresh evidence, current line): `fixed` (record the fixing commit), still present (re-verify the failure path -- stale evidence is not carry-over justification), or `outdated` (the referenced code is gone).
4. MINT the new session (same recipe) and annotate: still-present findings re-anchored at current lines with their stable `[F<id>]`, new findings with fresh ids.
5. UPDATE the ledger (anchor edit or `--body-file`), flip the task back to `review`, post `cortex_update` with the round verdict. Aim for first-pass completeness: over 80% of well-run reviews need at most one iteration (Sadowski et al., ICSE 2018) -- rounds should converge, not drift.
6. DONE: the user accepts -> flip the task `done`; leave all tuicr sessions as read-only history.

### Guidance for the human reviewer (include in the handoff message)

- Keep a review sitting to ~200-400 LOC and <=60-90 min (Cisco/SmartBear study); if the diff exceeds that, say so and suggest splitting by file or commit.
- The agent pipeline owns the defect sweep; the human's highest-value role in the TUI is design, intent, and understandability judgment -- reviews by humans surface mostly small low-level and maintainability issues (Bacchelli & Bird, ICSE 2013; Beller et al., MSR 2014), and automation exists so humans focus on the meaningful (Sadowski et al., ICSE 2018).
- Prompt round trips: respond within a day; long review intervals measurably reduce usefulness (Ram et al., EMSE 2023).

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

8. LOCAL MODE LIFECYCLE. For tuicr local reviews the same task holds the findings ledger and round log. Status flow: `draft` while annotating round 1 -> `review` when handed to the human -> `open` when the user signals a new round (their signal IS the explicit confirmation to edit the task) -> `review` again after the round's ledger update -> `done` on user acceptance. Title local tasks `Local Review: <branch>@<head-sha> -- round N`; in the body template replace the `Author: <author> | <base> -> <head>` line with `Scope: <base>..HEAD + worktree | lane: <lane>`. Ledger updates while the task sits in `review` during an ACTIVE local-review loop are pre-authorized (user standing rule); the generic never-edit-`review`-status rule applies only outside an active loop.

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
- NEVER `:submit`/export tuicr annotations to a forge -- local drafts only
- ALWAYS mirror every tuicr annotation in the cortex ledger under a stable finding id; NEVER track findings by line number alone
- NEVER mutate or delete old tuicr sessions -- they are read-only archives; the cortex ledger is the only cross-round memory
- ALWAYS re-validate open findings against the new code each round; NEVER carry a finding forward on stale evidence
- ALWAYS run the pre-handoff validation (consistency, evidence, coverage, anchors) before flipping a local review to `review`
- NEVER report style, formatting, or theoretical concerns -- bugs only
- Verify findings against relevant source context, callers/contracts, and tests; expand reads when needed, not merely to satisfy a stage.
- Use relevant authorized validation or still-applicable evidence; explicitly report unperformed checks and blockers. Never infer test success from missing counts or an unverified claim.
- Label multi-model validation only when the fixed distinct-model quorum is met; preserve directly supported issues with an honest degraded/unfiltered label when consensus is unavailable.
- If no real issues found, output PASS with empty sections
- Keep findings terse -- one line each, explain "why" not "what"
- Skip checklist dimensions that don't apply
- No filler, no preamble, no verbose explanations
