---
name: pr-reviewer
description: Multi-model critic consensus reviews in two modes -- thorough (default; bugs plus design, tests, operability, compatibility, maintainability and docs) or static (bugs, security and logic only) -- false-positive filtered, with structured severity and go/no-go verdicts. Targets GitHub PRs, one at a time or as a batch with one reviewer per PR (ending in an approval-gated GitHub review with inline comments; PRs the user already approved are skipped; re-reviews re-validate prior findings and post a new review) or local WIP/branch reviews via tuicr annotation sessions, both with a cortex findings ledger
# extended: multi-stage pipeline with multi-model critic consensus and embedded evaluation criteria
---

# PR Reviewer Skill

The default review product is a Cortex draft plus, for GitHub PRs, a drafted GitHub review with inline comments that is posted only after explicit user approval (Stage 6); load or reuse the `cortex` skill when that persistence is within the requested scope. If the user explicitly requests answer-only/no external records, skip Cortex and clipboard writes, return the structured review inline, and present any Stage 6 draft inline without posting. Do not change an explicitly requested durable product silently; report a persistence blocker if it cannot be delivered.

## Purpose

Review PRs for code health. Output a minimal, actionable review, then draft a GitHub review with inline comments for the surviving findings. Nothing reaches the PR until the user approves the exact draft and its event (COMMENT, REQUEST_CHANGES, or APPROVE). Uses a multi-model critic consensus to aggressively filter false positives before reporting.

Goal: "Would merging this improve the codebase?"

Two targets: GitHub PRs (default flow below; re-reviews follow `PR re-review rounds`) and local WIP/branch reviews (see `Local review sessions with tuicr`). Both persist to the same cortex review task.

## Review modes

Every review (single PR, re-review, batch or local) runs in one of two modes. Pick the mode from the request before Stage 1 and name it in the review header.

- THOROUGH (default): a full code-health review. It covers everything STATIC does, plus design, tests, error handling and operability, performance, compatibility, maintainability and documentation. Use it unless the request asks for static mode.
- STATIC: bugs, security issues and logic errors only, as a narrow defect sweep. Use it when the request says "static review", "static mode" or "bugs only".

Both modes use the same pipeline, evidence bar and posting gates. They differ only where a stage names a mode: what Stage 2 looks for, the critic criteria in Stage 3, and the findings in the Stage 5 template. A re-review uses the mode the request names; otherwise it uses the mode in the previous round's log line.

## Process

### Stage 1: Fetch PR context

MODE FORK: if the review target is LOCAL work (WIP, uncommitted changes, or a feature branch, with no PR source), skip this stage's `gh` retrieval and follow `Local review sessions with tuicr` below for scope and session mint; stages 2-4 apply with 'the PR' meaning the review-scope diff, and intent comes from the user's request, branch name, and commit messages instead of a PR description.

PRIOR-APPROVAL GATE (PR mode): run this before the re-review fork, Stage 2, any delegation, and any Cortex write. An approval the posting identity already gave stands until the PR's own patch changes, so a verdict that has not changed NEVER needs a second review or post. GitHub is the source of truth here, including approvals given outside this skill and missing from the ledger.

1. Read the posting identity (`gh api --method GET user --jq .login`), the revisions (`gh pr view <source> --json headRefOid,baseRefOid`), and the reviews (`gh api --method GET repos/{owner}/{repo}/pulls/{number}/reviews --paginate`). Take that login's latest review whose state is not `COMMENTED`; a later comment does not withdraw an approval.
2. `APPROVED` at the current head: STOP. No analysis, critics, Cortex writes, or GitHub draft. Report that the PR is already approved at that head, with the review URL and any `open` findings in its review task.
3. `APPROVED` at an older commit: compare the PR's own patch then and now. `git diff <base-oid>...<approved-commit> | git patch-id --stable` and the same for the head give equal ids when only the base moved (a rebase); fetch the approved commit by SHA if it is not local. Equal ids: STOP as in step 2 and say the patch is unchanged since the approval. Different ids, or no comparison possible: review only what changed since the approval (`git range-diff <base-oid> <approved-commit> <head>`), through `PR re-review rounds` when a review task exists. No new surviving finding means the approval stands: post nothing; if a review task exists, add the round's log line and return it to `done`. Surviving findings go in a Stage 6 draft that carries only those findings, as `COMMENT` or `REQUEST_CHANGES`, never a second `APPROVE`.
4. `DISMISSED`, `CHANGES_REQUESTED`, or no such review: continue normally. A dismissed approval no longer counts on GitHub, so a PASS round still drafts a new `APPROVE`.

For several PRs, follow `Batch PR reviews`, which runs this gate for each PR before any reviewer starts and lists the skipped PRs with their approval links. Review an approved PR in full only when the user explicitly asks for a fresh review of that PR.

RE-REVIEW FORK: if the user asks to re-review a PR or check its fixes, or the PR already has a `PR Review #<number>:` cortex task, follow `PR re-review rounds` below; this stage still runs against the new head.

Use the explicitly provided PR URL/number or pinned source context first. Only when no source was supplied, resolve the current PR with `gh pr view --json number -q .number`; ask once if no unique PR can be identified. Do not check out or detach the user's branch to begin a read-only review.

- Capture metadata with `gh pr view <source> --json title,body,author,baseRefName,baseRefOid,headRefName,headRefOid,files,additions,deletions,url,updatedAt` and retain the reviewed base/head revisions.
- Use the supplied revision-scoped diff or `gh pr diff <source>` as the PR scope. Pair live retrieval with its captured revisions; if references change during retrieval, refresh the affected evidence before relying on it.
- Read relevant source at the pinned revision through authorized read-only tools. If objects are already local, `git show <sha>:<path>` and `git diff <base-sha>...<head-sha>` avoid assuming the active HEAD is the PR head. Missing source is a gap to report, not permission for an automatic checkout/fetch/install workflow.
- Use `git_blame` for material prior-change rationale when that evidence is needed; fetch linked issues only when they affect the review.
- Fetch or reuse applicable PR comments for early deduplication: `gh api repos/{owner}/{repo}/pulls/{number}/comments --jq '.[] | {id, path, line, body}'`. Note incomplete comment coverage instead of claiming exhaustive deduplication.
- Keep API retrieval read-only; the ONLY PR write in this skill is the approved Stage 6 post. If adding query fields with `gh api`, explicitly use `--method GET`; field arguments otherwise change its default method.

### Stage 2: Deep analysis

Read the PR description for intent and use applicable context already supplied. Before reporting a finding, inspect the changed code plus the relevant definitions, callers, data contracts, and tests needed to establish a reachable failure. Expand to full files when those relationships require it; do not explore unrelated code or reread an unchanged snapshot merely because a stage changed. Use registered search/structural tools for unresolved questions.

STATIC: focus on BUGS, SECURITY, and LOGIC -- not style or code quality.

THOROUGH: everything STATIC looks for, then the rest of the change's code health. Work through these dimensions in order, because a design problem can make line-level comments moot:
- Design: the change belongs where it is, follows the codebase's existing patterns and boundaries, and adds no coupling or abstraction the PR does not need. Name the existing pattern it departs from (file:line).
- Tests: the tests exercise the new behavior and its edge cases, would fail if the code were broken, and check what their names claim.
- Error handling and operability: failures surface with enough context to debug; logs, metrics, feature flags, migrations and rollback are safe.
- Performance: only with evidence, such as a hot path, an unbounded loop or query, or a measured cost.
- Compatibility: public APIs, config, schemas, wire formats and stored data, including what existing callers and old data do after the change.
- Maintainability and readability: misleading names, duplication of an existing helper, dead code, control flow a reader cannot follow, and comments that are wrong or narrate the code.
- Documentation: the PR description, docs, changelog and comments match what the code now does.

Every THOROUGH finding carries its category (Bug, Security, Design, Tests, Operability, Performance, Compatibility, Maintainability or Docs), its cost (who pays and how: users, callers, on-call, or the next reader), and a specific suggested change.

Severity tiers:
- Critical: type mismatches causing runtime errors, nil/null crashes, SQL injection, auth/authz bypasses, data corruption/loss, deadlocks, race conditions, memory leaks, unbounded resource usage, breaking API changes
- Medium: N+1 queries degrading performance, missing error handling on critical paths, improper transaction handling, config errors affecting functionality, missing validation on user inputs, incorrect error/status codes. THOROUGH also rates as Medium a non-bug finding likely to cause a defect or a costly change soon: no test on a risky new path, an interface that cannot evolve without breaking callers, or a misleading name on a public API.
- Minor: bounded concrete behavioral defects or newly introduced public-API documentation errors with a demonstrated misuse path. THOROUGH also rates as Minor a finding that costs readers or maintainers without a near-term defect. In STATIC mode, missing tests alone are not a finding.
- Nit (THOROUGH only): a small optional improvement, such as a clearer name or a simpler expression. Nits never change the verdict.

Design, Tests, Maintainability and Docs findings top out at Medium; Critical is for findings that cause a failure on their own.

Do NOT report, in either mode: formatting or anything a configured linter or formatter catches, theoretical optimizations, pre-existing issues the PR does not touch or make worse, redesigns beyond the PR's scope, and preferences with no stated cost. STATIC also leaves out naming, style, tests, "consider using X instead" suggestions and other code-quality concerns.

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

Impact per finding (1-2 sentences): who is affected (users, services) and what happens (corruption, outage, incorrect behavior)? For a THOROUGH non-bug finding, the impact is its cost: who pays (callers, on-call, the next reader) and how.

Pre-filter (reduce critic workload by catching obvious false positives early):
- Do NOT flag missing nil checks without a concrete reachable failure path
- Do NOT flag PR changes as regressions without evidence they are unintended
- Respect encapsulation (don't re-litigate what the called method owns)
- Require EVIDENCE before flagging failure paths -- "could plausibly fail" is not sufficient
- Match standards to context (rake tasks, CLI tools, test fixtures != production code)
- THOROUGH: drop a design or maintainability candidate that cannot name its cost or the codebase convention it breaks, and merge repeats of one nit into a single finding that lists every line

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

Send the critics the criteria for the review's mode, and the mode's severity tiers from Stage 2.

STATIC criteria. REJECT if any of these apply:
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

THOROUGH criteria. REJECT if any of these apply:
- Formatting, or anything a configured linter or formatter catches
- A preference with no stated cost to users, callers, operators or readers
- Theoretical optimization or speculative concern without evidence
- Scope creep (redesign beyond the PR)
- Hallucinated standard, API behavior or codebase convention
- Pre-existing issue the PR does not introduce or make worse
- Missing nil/null check with no reachable failure path
- An intentional design decision the PR explains, unless the finding shows a concrete defect in it
- Encapsulation re-litigation (called method already handles it)
- Production standard applied to scripts, CLI tools, or test fixtures
- Severity overstated enough to mislead the author (a nit sold as Medium)

KEEP only if ALL true:
- ACCURATE: the claim matches the code, verified by reading it
- INTRODUCED or made worse by this PR (added or modified lines, or missing tests for them)
- ACTIONABLE: names a specific change the author can make
- WORTH THE AUTHOR'S TIME at its stated severity

Note in the Validation section how many critic sessions were spawned and total findings
evaluated for cost transparency.

### Stage 4: Deduplication

Use the comment snapshot already screened before delegation to make the final deduplication decision. Re-fetch only when relevant comments changed or current coverage is materially required, not simply because this stage was reached.

LOCAL MODE: there is no PR comment snapshot. Deduplicate against the cortex findings ledger from prior rounds: a candidate matching an existing `open`/carried finding (same essence -- category + offending code pattern, never line numbers) IS that finding -- re-anchor and continue it under its F-id instead of creating a new one. A candidate matching a `fixed`/`wontfix` entry is a regression or repeat -- name its F-id explicitly instead of minting a fresh finding.

PR RE-REVIEW: the reviewer's own prior-round comments (the ledger's `github thread` URLs) are NOT duplicates to drop -- they are the prior findings under re-validation, matched with the same F-id rules as local mode. Comments from everyone else are deduplicated as below.

A finding is a DUPLICATE if:
- Same issue already raised by any commenter (even if worded differently)
- Same file, overlapping lines (within 5 lines), same problem
- An existing comment covers a parent/child of the same issue

When uncertain, mark as duplicate. Better to skip a duplicate than repeat one.

### Stage 5: Output

Use applicable revision-scoped CI/local evidence first. Before asking the author to run a focused check or treating reported test failures as an unresolved validation gap, determine whether existing evidence or an authorized, feasible check can settle the question yourself. When a reported failure materially affects the verdict and its baseline is unknown, compare the same narrow command and failure signatures at the pinned base and head; if the base moves, check relevant source changes before reusing the comparison. Inspect the command and its side effects first; do not execute a blanket build/test/lint cycle or a modifying formatter merely to complete a review stage. Record each performed command and outcome; label unperformed validation and specific blockers explicitly.

If execution requires a checkout/worktree, obtain authorization when not already supplied and protect the user's dirty worktree. A missing path in the current checkout is not proof that the required scope is unavailable when an authorized isolated checkout can provide it. A disposable worktree isolates file changes, not network access or credentials; it is not a security sandbox. If the required scope/environment is unavailable or the check is unsafe, continue only with permitted static inspection and report the concrete blocker—no unapproved installs, destructive cleanup, or claims that tests passed.

For Terraform workspaces: `terraform validate` confirms schema conformance but does NOT validate semantic correctness of attribute interactions. Cross-reference provider documentation for resource types in the diff to verify behavioral intent matches configuration.

Verdict system:
- PASS: No substantiated significant issues in the reviewed scope; this does not certify unperformed validation or guarantee merge safety.
- GO WITH FIXES: Minor issues, not blocking.
- NEEDS REVIEW: Moderate issues needing human attention before merge.
- BLOCK: Critical bugs. Do NOT merge until fixed.

In THOROUGH mode the verdict follows the highest surviving severity in any category, and a review with only nits is PASS.

Render the review using this template:

```markdown
# PR #<number> - <title>

Author: <author> | <base> -> <head> | Mode: THOROUGH / STATIC
Verdict: PASS / GO WITH FIXES / NEEDS REVIEW / BLOCK

## Summary
<2-3 plain sentences: what the PR does, the verdict, and the findings that matter most>
e.g., "This PR moves cache eviction into the request path. Two critical bugs block it: eviction can drop in-flight entries, and the new TTL is never read."

## Findings

### Critical
- `file:line` -- **Title** (<category>; THOROUGH only): description with evidence and code snippets.
  Impact: <concrete impact or cost>. Suggestion: <fix>.
  Critic consensus: <votes>/<critics> KEEP

### Medium
- ...

### Minor
- ...

### Nits (THOROUGH only)
- `file:line` -- **Title** (<category>): the suggestion in one line.

### Praise
- `file:line` -- description

### Filtered (for reference)
<N> findings filtered by critic consensus:
- `file:line` -- <title> (votes: <votes>/<critics> KEEP -- <primary rejection reason>)

## Validation
- `<command>` -- <result>
- Critic consensus: <N> sessions spawned, <filtered> of <total> candidate findings filtered

## Checklist
- [x] Design  ...

(only dimensions evaluated: x = good, ~ = n/a, - = concern noted in findings;
 THOROUGH lists every Stage 2 dimension)
```

Omit empty finding subsections (except for PASS with no findings). Clearly distinguish consensus-filtered findings from directly verified findings whose consensus was unavailable/below quorum. Use the Cortex persistence section for the configured durable product unless the user explicitly requested answer-only/no external records; that mode returns the review inline without Cortex or clipboard writes. For GitHub PRs, the cortex body also carries the findings ledger and round log (see `PR re-review rounds`), and the review ALWAYS continues to Stage 6 (which drafts nothing when the prior-approval gate says the approval stands).

### Stage 6: GitHub review draft, approval, and posting

PR mode only -- local tuicr reviews end at their own Stage 5. This is the FINAL step of every GitHub PR review and re-review round, including PASS (an `APPROVE` review with no inline comments), unless the Stage 1 prior-approval gate found that the posting identity's approval stands; then nothing is drafted or posted. Nothing is written to the PR until the user explicitly approves the exact draft presented. In explicit answer-only mode, present the draft inline and stop: posting and Cortex close-out are external records.

SHUTTLE HANDOFF: when the request tells you to hand the review to Shuttle with `shuttle_review_draft`, Shuttle shows the draft to the user and posts it, so this stage changes. Run steps 1 to 3 and 5, then call `shuttle_review_draft` once: the review body as `summary`; the recommended event as `verdict` (APPROVE is approve, COMMENT is comment, REQUEST_CHANGES is changes); and one finding per inline comment with `severity` (Critical is high, Medium is medium, Minor is low, Nit is nit), `path`, the anchored `line` and the comment as `body`. A finding about a whole file goes in without `line`; a whole-PR finding stays in `summary`. Skip steps 4 and 6 to 10: build no payload file and post nothing. Leave the Cortex task `draft`, with a round-log line ending "handed to Shuttle". The draft the user sees is the summary and the inline comments, nothing else: the ledger, checklist, validation log and filtered-findings list stay in the Cortex body and NEVER appear in the draft.

1. SELECT: one inline comment per surviving finding (CERTAIN/LIKELY; consensus-filtered, or labeled not consensus-filtered), anchored on lines the PR changed at the pinned head (`side: "RIGHT"`; add `start_line` + `start_side` for ranges). Findings without a changed-line anchor (unchanged code, whole-PR concerns) go in the review body. Filtered findings never appear; praise stays to one line in the body. Start each nit's comment with `Nit:` so the author knows it is optional. Fewer, better comments.
2. ANCHOR CHECK: from the pinned revision-scoped diff, confirm every `line`/`start_line` falls on the new side of one hunk of that file (added or context line; a range stays within one hunk) and that the source line there is the code the finding describes. A single out-of-diff line makes GitHub reject the whole review (422).
3. WRITE brief: the review body is 2-4 plain sentences -- what the PR does, the verdict, and the findings that matter most. Each inline comment is ONE short paragraph of at most three sentences: what is wrong, what it costs, and the fix. Quote code only when the problem is not visible in the diff hunk the comment sits on; never attach validation logs, checklists, critic tallies or praise padding to the draft. Polite, specific, first person, written like a colleague leaving a GitHub review. No internal jargon in public text (F-ids, critic tallies, cortex references) and no tracking params (`?utm_source=`).
4. BUILD: write each body to its own markdown file in a scratch directory (e.g. `/tmp/pr<n>-review/`) and assemble the payload with `jq` -- NEVER hand-escape JSON -- pinned to the reviewed head:
   ```bash
   jq -n --arg commit_id "$HEAD_SHA" --arg event COMMENT \
     --rawfile body body.md --rawfile c1 comment-1.md \
     '{commit_id: $commit_id, event: $event, body: $body,
       comments: [{path: "<path>", start_line: 10, start_side: "RIGHT", line: 12, side: "RIGHT", body: $c1}]}' \
     > github-review-draft.json
   ```
   Validate before presenting: `jq` parses the file and `grep -c utm_` returns 0.

   The summary ALWAYS travels as this payload's `body`, next to its `event`, so the verdict and its explanation are ONE review. GitHub shows an approval with a body as "<login> approved these changes" with the body in a nested "<login> left a comment" card; that card is part of the review, not a separate comment. NEVER post the summary as an issue comment, or as a second review next to a body-less approval.
5. RECOMMEND the event from the verdict; the user makes the final call:
   - PASS -> `APPROVE` (body only)
   - GO WITH FIXES -> `APPROVE` with the non-blocking comments, or `COMMENT`
   - NEEDS REVIEW -> `COMMENT`
   - BLOCK -> `REQUEST_CHANGES`

   Prefer `COMMENT` over `REQUEST_CHANGES` when the decisive findings are documentation-only, runtime-unverified, or not consensus-filtered. When the reviewer authored the PR, GitHub accepts only `COMMENT`. Omitting `event` creates a PENDING review the user can finish in the GitHub UI.
6. PRESENT for approval: the exact review body, each inline comment with `path:line(s)`, the recommended event and alternatives, the payload path, the posting identity (`gh api --method GET user --jq .login`), and the post command. STOP and wait. Requested edits -> revise, repeat steps 2-4, and re-present. Approval of the draft as presented (e.g. "post it") authorizes exactly that payload and event; naming a different event (e.g. "request changes") changes only `event`.
7. PRE-POST CHECK, immediately before posting: the PR head still equals `commit_id` and the comment/review snapshot is unchanged since drafting. Head moved -> STOP, re-validate the affected findings and anchors against the new head, and re-present; NEVER post stale anchors. New comments -> deduplicate, and re-present if any overlaps a drafted comment.
8. POST ONCE: `gh api --method POST repos/<owner>/<repo>/pulls/<n>/reviews --input github-review-draft.json > post-response.json`. NEVER blind-retry: on failure, first list `GET repos/<owner>/<repo>/pulls/<n>/reviews` for a review by the posting user at `commit_id` (a duplicate review is worse than a delay), then quote the error and propose a fix. Known 422s: a comment line outside the diff, approving or requesting changes on your own PR, and an existing pending review by the same user.
9. VERIFY: the response `state` matches the event (`COMMENTED`/`CHANGES_REQUESTED`/`APPROVED`), `commit_id` equals the pinned head, and the posted body equals the payload. Confirm every inline anchor through the full-schema endpoint:
   ```bash
   gh api --method GET repos/<owner>/<repo>/pulls/<n>/comments --paginate \
     --jq '.[] | select(.pull_request_review_id == <review-id>) | {path, start_line, line, side, position, html_url}'
   ```
   Each drafted comment must appear with its drafted `path`/`line`/`side` and a non-null `position`. Do NOT check anchors with `GET .../reviews/<review-id>/comments`: its legacy schema returns null `line`/`side` even for correctly anchored comments.

   Then confirm the post created exactly one item: one new review by the posting identity at `commit_id` in `GET repos/<owner>/<repo>/pulls/<n>/reviews`, and no new issue comment by it in `GET repos/<owner>/<repo>/issues/<n>/comments`.
10. CLOSE OUT only after step 9 passes: record the review URL, event, and each finding's comment URL in the ledger and round log, then `cortex_update` with status `done` and a message carrying the review URL and event, and confirm with `cortex show <id> --json`. If the user declines or defers posting, post nothing and leave the task `draft`; findings the user drops from the draft become `wontfix` with the user's rationale.

## PR re-review rounds

MODE TRIGGER: the user asks to re-review a PR or check the author's fixes, or the PR already has a `PR Review #<number>:` cortex task. One review task per PR: its body is the findings ledger and the ONLY cross-round memory, as in local mode. Locating that task by PR number is not plan discovery -- plans are still linked only when the user names one. The Stage 1 prior-approval gate runs before this section and can end the round before step 1.

LEDGER: every PR review body, round 1 included, carries the `Findings ledger` table and `Round log` defined in `The cortex findings ledger`, plus a `github thread` column holding each finding's posted comment URL (`body` when raised only in the review body; `-` until posted). Round-log lines record head, mode, verdict, event, and review URL, e.g. `r1 @66bf050 thorough: NEEDS REVIEW, COMMENT, <review-url>`.

1. LOCATE: `cortex ls --json -l "$LANE" -t pr-review -q "@PR Review #<number>:"`, keeping titles that start with `PR Review #<number>:` (the listing includes `done` tasks). Exactly one -> use it; none -> run a first review; several -> ask once. The re-review request IS the explicit confirmation to reopen it: `cortex_update` with status `draft` and a `round <N> @<new-head>` message.
2. FETCH: run Stage 1 against the new head, and read the prior rounds' threads (the ledger's `github thread` URLs) from the full-schema comments endpoint, replies included. Author replies ("fixed in X", "intentional", disagreement) feed step 3. A null `position` marks an outdated thread whose code changed.
3. RE-VALIDATE every `open` finding against the new head as a full re-check with fresh evidence -- NEVER carry-over: `fixed` (record the fixing commit), still present (re-verify the failure path, re-anchor at the current line), `outdated` (the referenced code is gone), or `wontfix` (the user accepts the author's rationale). Weigh author pushback on its merits: withdraw the finding with the reason when the pushback holds; otherwise keep it and surface the disagreement to the user.
4. NEW CHANGES: review the commits since the last reviewed head (`gh api --method GET repos/<owner>/<repo>/compare/<old-head>...<new-head>`, `git diff` when objects are local, or the full PR diff when the old head was force-pushed away) through Stages 2-4 with full-PR context. A candidate matching a ledger finding's essence IS that finding. Send only new or changed findings to Stage 3; reuse prior critic consensus when a finding and its code region are unchanged.
5. OUTPUT: update the same task body (this round's review template, ledger statuses and locations, round log) via anchor-based edits or a `--body-file` rewrite.
6. NEW GITHUB REVIEW through Stage 6, unless the prior-approval gate says the posting identity's approval stands; NEVER edit, dismiss, resolve, or reply to prior reviews or threads unless the user explicitly asks. The body lists fixed findings (with fixing commits), still-present findings (linking their existing threads), and new findings. Inline comments go to new findings and to still-present findings whose prior thread is outdated (re-anchored, linking the prior thread); a still-present finding with a live thread is referenced in the body only, to avoid duplicate threads. Recommend the event from the round verdict (e.g. every finding fixed -> `APPROVE`). Approval, pre-post check, posting, verification, and close-out to `done` follow Stage 6 unchanged.

## Batch PR reviews

MODE TRIGGER: the user asks for reviews of two or more PRs in one request (a list of numbers, an author's PR list, or a stack). Every PR gets the same gate, the same review mode, the same reviewer instructions, the same output files, one shared critic round and one approval table, so verdicts are comparable within and across batches. This is the only mode that delegates whole reviews; a single PR uses the normal flow.

1. RESOLVE: review exactly the PRs the user named; a linked PR list scopes the lookup but never adds PRs. Capture `number,title,author,state,isDraft,baseRefName,baseRefOid,headRefName,headRefOid,additions,deletions,changedFiles,url` for each. A PR whose base branch is another PR's head branch is stacked: review only its own base..head. Ask once about closed, merged or missing PRs.
2. GATE: run the Stage 1 prior-approval gate for every PR. A skipped PR gets no reviewer, no Cortex write and no draft; gate case 3 gets a DELTA reviewer.
3. LOCATE each remaining PR's review task (`PR re-review rounds` step 1). A task means RE-REVIEW mode; reopen it to `draft` now.
4. SOURCE: when a local clone of the repository exists, fetch each head into its own ref and verify it: `git fetch origin refs/pull/<n>/head:refs/pr-review/<n>-<head12>`, then confirm `git rev-parse` equals `headRefOid`, and fetch any missing base commit. This changes no branch or working tree. NEVER clone, check out, or reuse a ref that points at another commit. Without a clone, use the template's GH-ONLY source block. Note which runtimes are present or absent for the template's tooling note.
5. DISPATCH: fill `batch-reviewer-task.md` (in this skill's directory) once per PR, choosing one mode block, the scope block for the batch's review mode and one source block, and changing nothing else. Spawn every reviewer in one `spawn` call (waves of eight), all on this thread's model unless the user names one. Artifacts go to `<storage>/pr-reviews/pr<n>/`, where `<storage>` is `$BB_THREAD_STORAGE` when set, else one `mktemp -d` for the batch. Do not poll while they run.
6. CHECK each report before trusting it: `candidates.json` parses, every candidate has `anchor_verified: true` and evidence, and Coverage accounts for every file in the diff. Re-dispatch a failed or incomplete reviewer once with the same task; report a second failure instead of filling the gap yourself. Re-read each candidate's decisive lines at the pinned head, and rerun its reproduction when cheap, before the critic round.
7. CRITICS: run ONE Stage 3 round for the whole batch: one task per configured critic model carrying every candidate from every PR, grouped by PR with its pinned revisions and diff paths. Zero candidates across the batch skips the round. Check critics' factual side claims against source before repeating them.
8. FINALIZE each PR: write the critic results into `review.md` (filtered candidates move to Filtered) and recompute the verdict with Stage 5's rules. Refresh the head and `gh pr checks`: a moved head sends that PR back to step 5, and CI statements in `body.md` that are now stale get corrected. Persist with the Cortex recipe (new task or the reopened one) and attribute each with its verdict.
9. PRESENT: build each payload with Stage 6 steps 1-5, then show ONE table (PR, head, mode, verdict, Cortex task, recommended event, inline comment count) with links to every body and comment file, followed by the skipped PRs and why. Every row is a real proposal; NEVER list optional or redundant drafts. A blanket approval such as "post them" covers exactly the rows in the table; any other mix is named by PR number.
10. POST each approved PR in turn through Stage 6 steps 7-10: pre-post check, post once, verify, close out. Finish with one table of review URLs and events, plus the findings left open.

## Local review sessions with tuicr

MODE TRIGGER: the user asks to review local work -- WIP, uncommitted changes, or a feature branch -- with no PR source. Stages 2-4 (deep analysis, critic consensus, deduplication) run unchanged against the local diff; Stage 1 and Stage 5 fork as below.

Architecture: tuicr is ONLY the live annotation transport between agent and human. The cortex review task is the durable ledger and the ONLY memory across rounds. Tuicr sessions are disposable, HEAD-pinned views -- never read old sessions for context, never mutate them.

Load the `tuicr` skill for all session mechanics (discovery, launch, headless mint, comment semantics, diff reconstruction). This section defines only the review protocol layered on top. A pr-reviewer local review IS the tuicr skill's 'agent review' workflow with pre-authorized comment writing -- do not re-ask for approval to annotate the session you minted.

AUTHORIZATION: An explicit request to run this local-review workflow pre-authorizes bounded control of an available supported multiplexer (including Herdr) to create and manage the workflow's own fresh `tuicr` pane/session. Do not ask separately for multiplexer permission. Preserve the caller's focus, operate only in the requested repository and review scope, and close only panes this workflow created. Ask only when the repository/session target is ambiguous or an operation would exceed these bounds; this authorization never extends to unrelated panes, agents, workspaces, or destructive session control.

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

9. PR MODE LIFECYCLE. Status flow: `draft` from `cortex add` through the Stage 6 approval -> `done` once the approved review is posted and verified (Stage 6 step 10) -> a re-review request reopens `done` -> `draft` (the request IS the explicit confirmation) -> `done` again after that round's review is posted and verified. A declined or deferred post leaves the task `draft`. A PR that the prior-approval gate stops leaves its task unchanged: do not reopen it. PR-mode tasks never sit in `review`, so ledger and body updates during an active PR round need no further confirmation.

## Output Format

- For authorized durable output, persist the review per the recipe above (repo lane, `draft`, `pr-review` plus supplied-plan tags except reserved `plan`); leave priority unset unless explicitly requested.
- Report the created task ID only after persistence succeeds; its body is viewable via `cortex show <review-id>`. For explicit answer-only mode, return the structured review inline instead.
- Copy to clipboard only within the requested output scope and when the capability is available.
- For GitHub PRs, finish by presenting the Stage 6 draft for approval, or by reporting that the prior-approval gate skipped the PR and why; after an approved post, report the review URL, event, and verified anchors, and the closed-out task ID.

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
- NEVER write to the PR (reviews, comments, replies, resolutions, dismissals) without explicit user approval of the exact drafted payload; post ONLY that payload, ONCE, after the Stage 6 pre-post check
- ALWAYS run the Stage 1 prior-approval gate before any analysis, delegation, or Cortex write; the posting identity's approval stands until the PR's own patch changes, and a verdict that has not changed NEVER gets a second review or post
- ALWAYS end a GitHub PR review or re-review round with the Stage 6 draft (an `APPROVE` body for PASS), unless the prior-approval gate says the existing approval stands; verify anchors before presenting and again after posting
- ALWAYS send the summary as the `body` of the same review that carries the `event`; NEVER as a separate issue comment or a second review
- ALWAYS run batches through `Batch PR reviews`: reviewer tasks come from `batch-reviewer-task.md` with only placeholders and block choices filled, one critic round covers the whole batch, and one approval table lists only real proposals
- ALWAYS close out the cortex review task (`done`) only after the posted review is verified; leave it `draft` when posting is declined or deferred
- When a PR re-review round posts, ALWAYS post a NEW GitHub review; NEVER edit, dismiss, resolve, or reply to prior reviews or threads unless the user explicitly asks
- NEVER `:submit`/export tuicr annotations to a forge -- local drafts only
- ALWAYS mirror every tuicr annotation in the cortex ledger under a stable finding id; NEVER track findings by line number alone
- NEVER mutate or delete old tuicr sessions -- they are read-only archives; the cortex ledger is the only cross-round memory
- ALWAYS re-validate open findings against the new code each round (local and PR re-reviews); NEVER carry a finding forward on stale evidence
- ALWAYS run the pre-handoff validation (consistency, evidence, coverage, anchors) before flipping a local review to `review`
- NEVER report formatting, linter-level, or theoretical concerns in either mode; in STATIC mode report bugs, security issues and logic errors only; in THOROUGH mode every finding carries a category, its cost and a specific suggestion
- ALWAYS pick the review mode before Stage 1: THOROUGH unless the request asks for static mode, and send the critics that mode's criteria
- Verify findings against relevant source context, callers/contracts, and tests; expand reads when needed, not merely to satisfy a stage.
- Use relevant authorized validation or still-applicable evidence; explicitly report unperformed checks and blockers. Never infer test success from missing counts or an unverified claim.
- Label multi-model validation only when the fixed distinct-model quorum is met; preserve directly supported issues with an honest degraded/unfiltered label when consensus is unavailable.
- If no real issues found, output PASS with empty sections
- Keep each finding to one short paragraph: what breaks or what it costs, then the fix. The evidence lives in the review's work, not in a quote trail appended to every comment
- In any Shuttle or GitHub draft, write like a colleague: plain sentences, no headings, no section padding, brief by default
- When the request says to hand the review to Shuttle, end Stage 6 with `shuttle_review_draft` per its SHUTTLE HANDOFF paragraph; NEVER also build or post a GitHub payload
- Skip checklist dimensions that don't apply
- No filler or preamble; write the summary and every comment per the Agent Protocol's Writing for people
