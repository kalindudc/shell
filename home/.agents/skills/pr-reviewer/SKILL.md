---
name: pr-reviewer
description: Multi-model critic consensus reviews in two modes -- thorough (default; bugs plus design, tests, operability, compatibility, maintainability and docs) or static (bugs, security and logic only) -- false-positive filtered, with structured severity and go/no-go verdicts. Targets GitHub PRs, one at a time or as a batch with one reviewer per PR (ending in an approval-gated GitHub review with inline comments; PRs the user already approved are skipped; re-reviews re-validate prior findings and post a new review), with a cortex findings ledger
# extended: multi-stage pipeline with multi-model critic consensus and embedded evaluation criteria
---

# PR Reviewer Skill

The default review product is a Cortex draft plus, for GitHub PRs, a drafted GitHub review with inline comments that is posted only after explicit user approval (Stage 6); load or reuse the `cortex` skill when that persistence is within the requested scope. If the user explicitly requests answer-only/no external records, skip Cortex and clipboard writes, return the structured review inline, and present any Stage 6 draft inline without posting. Do not change an explicitly requested durable product silently; report a persistence blocker if it cannot be delivered.

## Purpose

Review PRs for code health. Output a minimal, actionable review, then draft a GitHub review with inline comments for the surviving findings. Nothing reaches the PR until the user approves the exact draft and its event (COMMENT, REQUEST_CHANGES, or APPROVE). Uses a multi-model critic consensus to aggressively filter false positives before reporting.

Goal: "Would merging this improve the codebase?"

Target: GitHub PRs (default flow below; re-reviews follow `PR re-review rounds`). Each PR persists to one cortex review task.

## Review modes

Every review (single PR, re-review or batch) runs in one of two modes. Pick the mode from the request before Stage 1 and name it in the review header.

- THOROUGH (default): a full code-health review. It covers everything STATIC does, plus design, tests, error handling and operability, performance, compatibility, maintainability and documentation. Use it unless the request asks for static mode.
- STATIC: bugs, security issues and logic errors only, as a narrow defect sweep. Use it when the request says "static review", "static mode" or "bugs only".

Both modes use the same pipeline, evidence bar and posting gates. They differ only where a stage names a mode: what Stage 2 looks for, the critic criteria in Stage 3, and the findings in the Stage 5 template. A re-review uses the mode the request names; otherwise it uses the mode in the previous round's log line.

## Process

### Stage 1: Fetch PR context

PRIOR-APPROVAL GATE: run this before the re-review fork, Stage 2, any delegation, and any Cortex write. An approval the posting identity already gave stands until the PR's own patch changes, so a verdict that has not changed NEVER needs a second review or post. GitHub is the source of truth here, including approvals given outside this skill and missing from the ledger.

1. Read the posting identity (`gh api --method GET user --jq .login`), the revisions (`gh pr view <source> --json headRefOid,baseRefOid`), and the reviews (`gh api --method GET repos/{owner}/{repo}/pulls/{number}/reviews --paginate`). Take that login's latest review whose state is not `COMMENTED`; a later comment does not withdraw an approval.
2. `APPROVED` at the current head: STOP. No analysis, critics, Cortex writes, or GitHub draft. Report that the PR is already approved at that head, with the review URL and any `open` findings in its review task.
3. `APPROVED` at an older commit: compare the PR's own patch then and now. `git diff <base-oid>...<approved-commit> | git patch-id --stable` and the same for the head give equal ids when only the base moved (a rebase); fetch the approved commit by SHA if it is not local. Equal ids: STOP as in step 2 and say the patch is unchanged since the approval. Different ids, or no comparison possible: review only what changed since the approval (`git range-diff <base-oid> <approved-commit> <head>`), through `PR re-review rounds` when a review task exists. No new surviving finding means the approval stands: post nothing; if a review task exists, add the round's log line and return it to `done`. Surviving findings go in a Stage 6 draft that carries only those findings, as `COMMENT` or `REQUEST_CHANGES`, never a second `APPROVE`.
4. `DISMISSED`, `CHANGES_REQUESTED`, or no such review: continue normally. A dismissed approval no longer counts on GitHub, so a PASS round still drafts a new `APPROVE`.

For several PRs, follow `Batch PR reviews`, which runs this gate for each PR before any reviewer starts and lists the skipped PRs with their approval links. Review an approved PR in full only when the user explicitly asks for a fresh review of that PR.

RE-REVIEW FORK: if the user asks to re-review a PR or check its fixes, or the PR already has a `PR Review #<number>:` cortex task, follow `PR re-review rounds` below; this stage still runs against the new head.

Use the explicitly provided PR URL/number or pinned source context first. Only when no source was supplied, resolve the current PR with `gh pr view --json number -q .number`; ask once if no unique PR can be identified. Do not check out or detach the user's branch to begin a read-only review.

- Capture metadata with `gh pr view <source> --json title,body,author,baseRefName,baseRefOid,headRefName,headRefOid,files,additions,deletions,url,updatedAt` and retain the reviewed base/head revisions.
- Use the supplied revision-scoped diff or `gh pr diff <source>` as the PR scope. Pair live retrieval with its captured revisions; if references change during retrieval, refresh the affected evidence before relying on it.
- Pin the PR's code before reading it. When the current directory is a clone of the PR's repository, fetch the head into its own ref, which changes no branch or working tree: `git fetch origin refs/pull/<n>/head:refs/pr-review/<n>-<head12>` on GitHub, or `git fetch origin <headRefOid>` on a server whose remote serves commits by SHA. Confirm `git rev-parse` of that ref equals `headRefOid`, and fetch the base commit by SHA if it is missing. Read and search the PR's version with `git show <ref>:<path>`, `git diff <base-oid>...<ref>` and `git grep <pattern> <ref> -- <paths>`, never the checkout's own files, which may be the default branch. Without a clone or a fetchable head, read through the server's own CLI or API (for example `gh`) and report what you could not read. NEVER clone, switch the user's branch, or install anything to get source.
- Use `git_blame` for material prior-change rationale when that evidence is needed; fetch the issues the PR links or closes (`gh pr view <source> --json closingIssuesReferences`, plus issue links in the description), which state its reason and feed Stage 2's intent and worth step; fetch other issues only when they affect the review.
- Fetch or reuse applicable PR comments for early deduplication: `gh api repos/{owner}/{repo}/pulls/{number}/comments --jq '.[] | {id, path, line, body}'`. Note incomplete comment coverage instead of claiming exhaustive deduplication. Automated reviewers, such as AI review bots, run on their own schedule: NEVER wait for one to post or for its pending check, and do not mention one in the review. The bot comments that exist now join this snapshot; the Shuttle handoff checks once more at the end.
- Keep API retrieval read-only; the ONLY PR write in this skill is the approved Stage 6 post. If adding query fields with `gh api`, explicitly use `--method GET`; field arguments otherwise change its default method.

### Stage 2: Deep analysis

Read the PR description for intent and use applicable context already supplied. Before reporting a finding, inspect the changed code plus the relevant definitions, callers, data contracts, and tests needed to establish a reachable failure. Expand to full files when those relationships require it; do not explore unrelated code or reread an unchanged snapshot merely because a stage changed. Use registered search/structural tools for unresolved questions.

Intent and worth, both modes. A correct change can still be the wrong change, and the user decides whether it should merge, so answer three questions for them. Start them before the defect sweep and finish them after Stage 4.
1. Intent: what problem does the PR solve, and what outcome does it promise? Take it from the description, the linked or closed issues and the commit messages, and name the source. If none of them says why, say so: that is useful to the user, and in THOROUGH mode a whole-PR Docs finding can ask the author to state it.
2. Does it get there, and only there: does the change deliver that outcome? Answer achieves, falls short (and why), or cannot tell from here (and what would show it, such as a live check). Then name any behavior it adds that the outcome does not need, such as an automatic expiry, matching for cases nobody has seen, a retry or a fallback; a description that only states a behavior ("auto-expires on X") has not said why it is needed. Finding no defects is not the same as achieving the goal, so say what you checked against the stated outcome.
3. Should we do this at all: weigh each point below, and cite the evidence for it or say it is missing.
   - Need: is the problem real and worth solving now? An issue, incident, metric, user request or failing check is evidence. The description's word alone is weak evidence, and you say so.
   - Alternatives: does code, configuration or a feature already do this (search the PR head for it, and reuse searches you already made for duplication), or would something smaller do it, such as a configuration change, a deletion, an upstream fix or a narrower change?
   - Cost: what does it add to maintain or run, against what it buys? For example a new dependency or service, a permanent flag, a migration, an irreversible step, or ongoing work for someone.
   - Fit: does it match the direction the repository states (README, docs, AGENTS.md, a roadmap issue), and are this repository and team the right owner?
   Skip a point with nothing to say, and do not invent doubts: "nothing argues against it" is a valid answer. End with a lean: worth doing, worth doing with changes, unclear until <what would settle it>, or doubtful because <reason>. When one question to the author would settle it, write that question as one sentence the user could post.
This answer is context for the user, not a finding. It reaches the author only if the user posts it, critics do not vote on it, and it does not change the verdict, which judges only the implementation. Verify each fact it cites by reading the source, as for any evidence.

Before looking for findings, load the knowledge the repository and your configured review specialists carry. Each step costs a few reads; skip a step whose source is unavailable and say so in Validation.

1. AGENTS.md: read every `AGENTS.md` at the PR head in each changed file's directory and its parents up to the repository root (`git show <ref>:<dir>/AGENTS.md`). Treat it as repository instructions: a finding it contradicts is dropped, and a rule it states can be a finding's evidence.
2. Specialists: pipe the changed paths (`git diff --name-only <base-oid>...<ref>`, or `gh pr view <source> --json files --jq '.files[].path'`) into `ruby --disable-gems <this skill's directory>/specialists.rb --repo <owner>/<repo> --meta <file with the PR title and body> --ref <ref>`, leaving out `--ref` when there is no local head ref. It reads the specialist sources in `$PR_REVIEWER_SPECIALISTS`, else `~/.config/pr-reviewer/specialists.json`, and says so when there are none. Each source's line names the checkout and commit it read, and its exemption file if it has one. For each `run` line, read that SKILL.md with `git -C <checkout> show <commit>:<skill>`, plus any `references/` file it tells you to read, and apply its checks. For each `judge` line, apply the skill only when the changed lines fit its `description` and `when_to_run`. A specialist's checks are guidance, not evidence: its findings still need source proof and still go to Stage 3, with the specialist's SKILL.md attached.
3. Past incidents (THOROUGH, production code): when an incident search tool is available, run at most two searches for incidents from the last twelve months about the service or component the PR changes, limited to incidents caused by code changes when the tool can filter by cause. Raise a finding only when this PR repeats a named incident's mechanism, and cite that incident.

Record in Validation which AGENTS.md files, specialists and incident searches were used.

STATIC: focus on BUGS, SECURITY, and LOGIC -- not style or code quality.

THOROUGH: everything STATIC looks for, then the rest of the change's code health. Work through these dimensions in order, because a design problem can make line-level comments moot:
- Design: the change belongs where it is, follows the codebase's existing patterns and boundaries, and adds no coupling or abstraction the PR does not need. Name the existing pattern it departs from (file:line).
- Tests: the tests exercise the new behavior and its edge cases, would fail if the code were broken, and check what their names claim.
- Error handling and operability: failures surface with enough context to debug; logs, metrics, feature flags, migrations and rollback are safe.
- Performance: only with evidence, such as a hot path, an unbounded loop or query, or a measured cost.
- Compatibility: public APIs, config, schemas, wire formats and stored data, including what existing callers and old data do after the change.
- Maintainability and readability: misleading names, duplication of an existing helper, dead code, control flow a reader cannot follow, and comments that are wrong or narrate the code.
- Simplicity and scope: everything the PR adds has to be earned by its stated intent and the evidence behind it.
  - Unrequested behavior: trace each behavior the change adds to the intent. Behavior nothing asks for, such as an expiry or kill date, matching for variants nobody has observed, retries, fallbacks, configuration or flags, is a finding (Design, or Operability when it changes production behavior on its own). Its cost is what it does that nobody wanted: a safeguard that switches itself off on a date while people believe it is on, or cases that are matched but never verified. A description or comment that only states the behavior ("expires on X", "mirrors Y") is not a reason for it.
  - More machinery than the job needs: when a simpler construct covers every case the intent and evidence require, such as a plain comparison, `ends_with`, a set or a direct call instead of a regex, a parser or a layer, raise it (Maintainability) and show the simpler form and the cases it covers. Its cost is the reader's: every later reader has to decode the construct to trust it, where a plain comparison is obvious. Coverage of variants nobody has observed is not by itself a reason for the complexity: first look for a simpler form that still covers them, often by leaning on what another condition already pins. Lean only on a condition that tests the same value: a check on the request's host does not pin the host named inside a header or URL it carries. Propose that form, and say whether it keeps the original scope or widens it. A form that widens it is a simplification only when you cite the PR's own evidence that the added matches are harmless (for example "a false match costs a real user nothing"); otherwise keep the scope and shorten only the grammar around it. If the first simpler form you try is too broad or too narrow, try another (a suffix check, or a short pattern anchored only where it matters) before you drop the finding; drop it only when no simpler form keeps the scope. A replacement narrower than the original is not a simplification unless the cases it drops cannot happen or do not matter, so do not trade cheap variants a client can produce for free (a query string, a trailing slash, a port, a change of case) for brevity. If you needed a test harness to convince yourself a construct is right, ask whether a simpler one would need none.
  - Code written with an agent often turns a word in the request into a mechanism ("temporary" into a hard expiry) or generalizes past the evidence. Look for both, whoever wrote the PR.
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
- THOROUGH: drop a design or maintainability candidate that cannot name its cost and either the codebase convention it breaks or the stated intent it goes beyond, and merge repeats of one nit into a single finding that lists every line

Scan for hidden artifacts: whitespace/alignment hunks hiding unrelated additions, AI-injected URL tracking params (`?utm_source=openai`), dead code introduced via conflict resolution.

For infrastructure-as-code (Terraform, Pulumi, CloudFormation) and unfamiliar library/provider APIs:
- Fetch provider/library documentation for every resource type or API being configured. For Terraform, fetch docs from provider GitHub repos (raw content), not registry.terraform.io (requires JS). Cross-reference `.terraform.lock.hcl` for the locked provider version and fetch docs for that version tag, not latest.
- Verify that attribute combinations are semantically valid (not just syntactically accepted)
- Trace default values to their runtime behavior: "what happens if a caller relies on this default?"

Self-review: If the reviewer is also the PR author, note the conflict in the Summary and adjust focus toward objective structural concerns rather than subjective design choices. For IaC repos without test suites, the Tests checklist dimension defaults to `[~] N/A`.

### Stage 3: Multi-model critic consensus

An empty screened batch skips this entire stage, including configuration/prompt reads. Otherwise read or reuse `~/.agents/skills/critique/critics.yml` and `critic-prompt.md` once. If configuration, dispatch, or actual identity verification is unavailable, report consensus unavailable/unverified and retain directly supported findings labeled not consensus-filtered. Do not create a probe or substitute-review loop to claim diversity.

1. Send the screened finding batch in one `spawn` tasks array with one task per configured critic, setting each task's `model` and `thinking` from that critic's entry in `critics.yml` (never one `model:thinking` string, never an empty `model`; the critique skill's Stage 3 says why). A critic that fails to start is reported, never replaced by another model. Include finding IDs/evidence, the `AGENTS.md` text Stage 2 loaded, the shared prompt and criteria, relevant diff/source snapshots, and a bounded read-only scope. When a Stage 2 specialist source names an exemption file, also include that file's text at the commit the script read. Write all of this once to a brief file in thread storage and give each critic a short task that names the file, as the critique skill's Stage 3 says; NEVER send a placeholder such as `CRITIC_TASK` as a task. Require KEEP/REJECT/ABSTAIN with rationale per finding; split only for a demonstrated context limit.
2. With N configured critics, multi-model validation requires KEEP from `max(2, floor(N / 2) + 1)` distinct, verified actual model identities, one vote per model. Requested labels and model self-reports do not verify dispatch: the model `spawn` names for each started minion does. NEVER ask a critic to state or look up its own model.
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
- A practice a specialist source's exemption file sanctions, for the claim and subject it names

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
- An intentional design decision the PR gives a reason for, unless the finding shows a concrete defect in it. A PR that only states a behavior ("auto-expires on X") has not given a reason for it
- Encapsulation re-litigation (called method already handles it)
- Production standard applied to scripts, CLI tools, or test fixtures
- A practice a specialist source's exemption file sanctions, for the claim and subject it names
- Severity overstated enough to mislead the author (a nit sold as Medium)

KEEP only if ALL true:
- ACCURATE: the claim matches the code, verified by reading it
- INTRODUCED or made worse by this PR (added or modified lines, or missing tests for them)
- ACTIONABLE: names a specific change the author can make
- WORTH THE AUTHOR'S TIME at its stated severity

A simplicity or scope finding is a factual claim when it cites the stated intent and either a simpler form or the behavior nothing asks for. Judge it on these rules:
- A simpler form that covers at least the cases that matter is not a preference: the complexity's cost falls on every reader, and that is a stated cost. KEEP it; REJECT it only when the proposed form drops a case the intent or evidence needs, including variants a client can produce for free. A form that also widens the match qualifies only when the finding cites the PR's own evidence that the added matches are harmless; without that citation, a widening form is a behavior change, not a simplification. Judge the finding against the best simpler form you can verify, not only the one it proposes: if a scope-preserving form exists, the complexity claim stands even when the proposed form is too broad. Name that form in your verdict, and the reviewer replaces the finding's suggestion with it before posting.
- Weigh a stated reason against the PR's own evidence. A reason the PR's own analysis undercuts, such as a time limit "for safety" on a change the PR shows is harmless to keep, is not a reason, and neither is a bare statement of the behavior.
- When an automatic expiry, timeout or kill switch ends a mitigation, the state it returns to is the problem the PR exists to fix. That is the behavior's cost, not a neutral baseline, and it needs no evidence that the replacement will be late.
- Precedent counts only from code that does the same job: a time window for a scheduled event is no precedent for ending a mitigation on a date.

Note in the Validation section how many critic sessions were spawned and total findings
evaluated for cost transparency.

### Stage 4: Deduplication

Use the comment snapshot already screened before delegation to make the final deduplication decision. Re-fetch only when relevant comments changed or current coverage is materially required, not simply because this stage was reached.

PR RE-REVIEW: the reviewer's own prior-round comments (the ledger's `github thread` URLs) are NOT duplicates to drop -- they are the prior findings under re-validation. A candidate matching an existing `open` finding (same essence -- category + offending code pattern, never line numbers) IS that finding -- re-anchor and continue it under its F-id instead of creating a new one. A candidate matching a `fixed`/`wontfix` entry is a regression or repeat -- name its F-id explicitly instead of minting a fresh finding. Comments from everyone else are deduplicated as below.

A finding is a DUPLICATE if:
- Same issue already raised by any commenter (even if worded differently)
- Same file, overlapping lines (within 5 lines), same problem
- An existing comment covers a parent/child of the same issue

When uncertain, mark as duplicate. Better to skip a duplicate than repeat one.

A concern another reviewer raised is not settled by being raised. While it is open, judge it on its merits against the stated intent and say in the For-you section whether you agree and why; do not set it aside as policy or preference without weighing it.

### Stage 5: Output

Use applicable revision-scoped CI/local evidence first. Before asking the author to run a focused check or treating reported test failures as an unresolved validation gap, determine whether existing evidence or an authorized, feasible check can settle the question yourself. When a reported failure materially affects the verdict and its baseline is unknown, compare the same narrow command and failure signatures at the pinned base and head; if the base moves, check relevant source changes before reusing the comparison. Inspect the command and its side effects first; do not execute a blanket build/test/lint cycle or a modifying formatter merely to complete a review stage. Record each performed command and outcome; label unperformed validation and specific blockers explicitly.

If execution requires a checkout/worktree, obtain authorization when not already supplied and protect the user's dirty worktree. A request or Shuttle preset that allows a detached worktree of the PR head is that authorization: create it with `git worktree add --detach <storage>/pr<n>-head <ref>`, run only focused checks that need no installs and finish within a few minutes, and remove it with `git worktree remove --force <storage>/pr<n>-head` when done. A missing path in the current checkout is not proof that the required scope is unavailable when an authorized isolated checkout can provide it. A disposable worktree isolates file changes, not network access or credentials; it is not a security sandbox. If the required scope/environment is unavailable or the check is unsafe, continue only with permitted static inspection and report the concrete blocker—no unapproved installs, destructive cleanup, or claims that tests passed.

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

## For you: should we do this? (never posted)
- **What:** <what the PR changes, in one sentence a reader new to it understands>
- **Why:** <the problem and the outcome it promises, and where that comes from (description, issue, incident); or "the PR does not say why">
- **How:** <how it gets there, in one or two sentences, then: achieves / falls short because ... / cannot tell from here until ...>
- **Extra:** <behavior or machinery the outcome does not need, such as an expiry, matching nobody asked for or a needless regex; or "nothing beyond the goal">
- **Should we:**
  - **Need:** <is the problem real and worth solving now, with its evidence or "the description's word only">
  - **Alternatives:** <existing code or a smaller change that would do, or "none found">
  - **Cost:** <what it adds to maintain or run, against what it buys>
  - **Fit:** <whether it matches the repository's stated direction and owner>
- **Lean:** <worth doing / worth doing with changes: ... / unclear until ... / doubtful because ...>
- **Unverified:** <what this review could not check that the decision depends on; or "nothing material">
- **Before merge:** <prerequisites outside the code, such as a dependency PR, a plan or a rollout step; or "none">
- **Ask the author:** <optional: one question you could post as written>

Write every label in this order, each as one or two short sentences, never a paragraph. What, Why, How, Lean and Unverified are always present; leave out another label, or a Should we line, only when it has nothing to say. Evidence, commands and file:line trails belong in Validation and the Cortex body, not here.

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

This is the FINAL step of every GitHub PR review and re-review round, including PASS (an `APPROVE` review with no inline comments), unless the Stage 1 prior-approval gate found that the posting identity's approval stands; then nothing is drafted or posted. Nothing is written to the PR until the user explicitly approves the exact draft presented. In explicit answer-only mode, present the draft inline and stop: posting and Cortex close-out are external records.

SHUTTLE HANDOFF: when the request tells you to hand the review to Shuttle with `shuttle_review_draft`, Shuttle shows the draft to the user and posts it, so this stage changes. Run steps 1 to 3 and 5. The "For you" section goes in `shuttle_review_draft`'s `notes`, as the labelled list from the Stage 5 template without its heading, never as paragraphs: Shuttle shows it above the draft and never posts it. If the tool has no `notes` field (an older Shuttle), open your final answer with it instead, under the heading "For you (not posted)". NEVER put it in `summary` or a finding. Just before the call, re-fetch the PR's review comments once and drop or merge any finding that a comment posted since Stage 1 already raises; automated reviewers often finish after you start. Do not wait for more comments. Then call `shuttle_review_draft` once: the review body as `summary`; the recommended event as `verdict` (APPROVE is approve, COMMENT is comment, REQUEST_CHANGES is changes); and one finding per inline comment with `severity` (Critical is high, Medium is medium, Minor is low, Nit is nit), `path`, the anchored `line` and the comment as `body`. A finding about a whole file goes in without `line`; a whole-PR finding stays in `summary`. When the tool offers them (Shuttle's auto post reads them), also give each finding `consensus` as its Stage 3 votes, `{keep, total}` with KEEP votes out of the critics that voted (leave it out when consensus was unavailable or below quorum, never invent votes); `evidence` as up to five decisive excerpts `{path, from, to, quote}` copied exactly from the pinned head, the lines the finding's verification read; and `category` as one or two words. Give `assessment` once for the whole PR: `risk` (low, medium or high) and `concerns`, the PR-level points a line comment cannot carry, each as `{kind, text}` with the kind that fits best: `description` (the description claims what the diff does not do, or leaves out what it does), `scope` (unrelated files, tests changed to pass, generated churn), `unverified` (a claim or result you could not check or run), `process` (CI, approvals, conflicts, rebase or merge state), `design` (a behaviour or design point the user should weigh) or `other`. Shuttle's auto post holds drafts by kind, so pick the kind honestly rather than to pass or fail it; empty when there are none. Skip steps 4 and 6 to 10: build no payload file and post nothing. Leave the Cortex task `draft`, with a round-log line ending "handed to Shuttle". The draft the user sees is the notes, the summary and the inline comments, nothing else: the ledger, checklist, validation log and filtered-findings list stay in the Cortex body and NEVER appear in the draft.

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
6. PRESENT for approval: first the "For you" section, labelled as not part of the payload, then the exact review body, each inline comment with `path:line(s)`, the recommended event and alternatives, the payload path, the posting identity (`gh api --method GET user --jq .login`), and the post command. STOP and wait. Requested edits -> revise, repeat steps 2-4, and re-present. Approval of the draft as presented (e.g. "post it") authorizes exactly that payload and event; naming a different event (e.g. "request changes") changes only `event`.
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

MODE TRIGGER: the user asks to re-review a PR or check the author's fixes, or the PR already has a `PR Review #<number>:` cortex task. One review task per PR: its body is the findings ledger and the ONLY cross-round memory. Locating that task by PR number is not plan discovery -- plans are still linked only when the user names one. The Stage 1 prior-approval gate runs before this section and can end the round before step 1.

LEDGER: every PR review body, round 1 included, carries the findings ledger and round log below. The `github thread` column holds each finding's posted comment URL (`body` when raised only in the review body; `-` until posted). Round-log lines record head, mode, verdict, event, and review URL.

```markdown
## Findings ledger

| id | severity | status | first seen | latest location | summary (why, one line) | github thread |
|----|----------|--------|------------|-----------------|-------------------------|---------------|
| F1 | critical | fixed  | r1 @8a04250 | src.rs:13 (r1) | divide-by-zero if compute() returns 0 | <comment URL> |

## Round log

- r1 @66bf050 thorough: NEEDS REVIEW, COMMENT, <review-url>
- r2 @7b08b13 thorough: F1 fixed in 7b08b13; F2 still present (re-validated, re-anchored src.rs:20); F3 wontfix (user: "intentional"); F4 new; GO WITH FIXES, COMMENT, <review-url>
```

Ledger rules grounded in prior art (SARIF, Gerrit, Semgrep, SonarQube): IDENTITY is location-independent; LOCATION is per-round; ONE canonical finding per issue.

- Statuses: `open | fixed | outdated | wontfix` (Semgrep/GitHub). `carried` is a per-round projection, never stored -- like Gerrit ported comments ("not copies"), a carried finding is the SAME finding rendered at a new location.
- Matching across rounds: match on the issue's ESSENCE -- category + the offending code pattern -- NEVER on line numbers (SARIF fingerprints: identity must be "resistant to changes... such as the line number").
- Porting rule (Gerrit): carry ONLY `open` findings into a new round; recompute the anchor; degrade line -> file-level -> review body. `fixed`/`wontfix` are never carried.

1. LOCATE: `cortex ls --json -l "$LANE" -t pr-review -q "@PR Review #<number>:"`, keeping titles that start with `PR Review #<number>:` (the listing includes `done` tasks). Exactly one -> use it; none -> run a first review; several -> ask once. The re-review request IS the explicit confirmation to reopen it: `cortex_update` with status `draft` and a `round <N> @<new-head>` message.
2. FETCH: run Stage 1 against the new head, and read the prior rounds' threads (the ledger's `github thread` URLs) from the full-schema comments endpoint, replies included. Author replies ("fixed in X", "intentional", disagreement) feed step 3. A null `position` marks an outdated thread whose code changed.
3. RE-VALIDATE every `open` finding against the new head as a full re-check with fresh evidence -- NEVER carry-over: `fixed` (record the fixing commit), still present (re-verify the failure path, re-anchor at the current line), `outdated` (the referenced code is gone), or `wontfix` (the user accepts the author's rationale). Weigh author pushback on its merits: withdraw the finding with the reason when the pushback holds; otherwise keep it and surface the disagreement to the user.
4. NEW CHANGES: review the commits since the last reviewed head (`gh api --method GET repos/<owner>/<repo>/compare/<old-head>...<new-head>`, `git diff` when objects are local, or the full PR diff when the old head was force-pushed away) through Stages 2-4 with full-PR context. A candidate matching a ledger finding's essence IS that finding. Send only new or changed findings to Stage 3; reuse prior critic consensus when a finding and its code region are unchanged.
5. OUTPUT: update the same task body (this round's review template, ledger statuses and locations, round log) via anchor-based edits or a `--body-file` rewrite. Redo the "For you" section only when the description, linked issues or scope changed since the last round, and otherwise say it is unchanged since that round.
6. NEW GITHUB REVIEW through Stage 6, unless the prior-approval gate says the posting identity's approval stands; NEVER edit, dismiss, resolve, or reply to prior reviews or threads unless the user explicitly asks. The body lists fixed findings (with fixing commits), still-present findings (linking their existing threads), and new findings. Inline comments go to new findings and to still-present findings whose prior thread is outdated (re-anchored, linking the prior thread); a still-present finding with a live thread is referenced in the body only, to avoid duplicate threads. Recommend the event from the round verdict (e.g. every finding fixed -> `APPROVE`). Approval, pre-post check, posting, verification, and close-out to `done` follow Stage 6 unchanged.

## Batch PR reviews

MODE TRIGGER: the user asks for reviews of two or more PRs in one request (a list of numbers, an author's PR list, or a stack). Every PR gets the same gate, the same review mode, the same reviewer instructions, the same output files, one shared critic round and one approval table, so verdicts are comparable within and across batches. This is the only mode that delegates whole reviews; a single PR uses the normal flow.

1. RESOLVE: review exactly the PRs the user named; a linked PR list scopes the lookup but never adds PRs. Capture `number,title,author,state,isDraft,baseRefName,baseRefOid,headRefName,headRefOid,additions,deletions,changedFiles,url` for each. A PR whose base branch is another PR's head branch is stacked: review only its own base..head. Ask once about closed, merged or missing PRs.
2. GATE: run the Stage 1 prior-approval gate for every PR. A skipped PR gets no reviewer, no Cortex write and no draft; gate case 3 gets a DELTA reviewer.
3. LOCATE each remaining PR's review task (`PR re-review rounds` step 1). A task means RE-REVIEW mode; reopen it to `draft` now.
4. SOURCE: when a local clone of the repository exists, fetch each head into its own ref and verify it: `git fetch origin refs/pull/<n>/head:refs/pr-review/<n>-<head12>`, then confirm `git rev-parse` equals `headRefOid`, and fetch any missing base commit. This changes no branch or working tree. NEVER clone, check out, or reuse a ref that points at another commit. Without a clone, use the template's GH-ONLY source block. Note which runtimes are present or absent for the template's tooling note.
5. DISPATCH: fill `batch-reviewer-task.md` (in this skill's directory) once per PR, choosing one mode block, the scope block for the batch's review mode and one source block, and changing nothing else. Spawn every reviewer in one `spawn` call (waves of eight), all on this thread's model unless the user names one. Artifacts go to `<storage>/pr-reviews/pr<n>/`, where `<storage>` is `$BB_THREAD_STORAGE` when set, else one `mktemp -d` for the batch. Do not poll while they run.
6. CHECK each report before trusting it: `candidates.json` parses, every candidate has `anchor_verified: true` and evidence, and Coverage accounts for every file in the diff. Re-dispatch a failed or incomplete reviewer once with the same task; report a second failure instead of filling the gap yourself. Re-read each candidate's decisive lines at the pinned head, and rerun its reproduction when cheap, before the critic round.
7. CRITICS: run ONE Stage 3 round for the whole batch: one task per configured critic model, each pointing at one brief file that carries every candidate from every PR, grouped by PR with its pinned revisions and diff paths. Zero candidates across the batch skips the round. Check critics' factual side claims against source before repeating them.
8. FINALIZE each PR: write the critic results into `review.md` (filtered candidates move to Filtered) and recompute the verdict with Stage 5's rules. Refresh the head and `gh pr checks`: a moved head sends that PR back to step 5, and CI statements in `body.md` that are now stale get corrected. Persist with the Cortex recipe (new task or the reopened one) and attribute each with its verdict.
9. PRESENT: build each payload with Stage 6 steps 1-5, then show ONE table (PR, head, mode, verdict, worth lean, Cortex task, recommended event, inline comment count) with links to every body and comment file, followed by the skipped PRs and why. Every row is a real proposal; NEVER list optional or redundant drafts. A blanket approval such as "post them" covers exactly the rows in the table; any other mix is named by PR number.
10. POST each approved PR in turn through Stage 6 steps 7-10: pre-post check, post once, verify, close out. Finish with one table of review URLs and events, plus the findings left open.

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

8. PR MODE LIFECYCLE. Status flow: `draft` from `cortex add` through the Stage 6 approval -> `done` once the approved review is posted and verified (Stage 6 step 10) -> a re-review request reopens `done` -> `draft` (the request IS the explicit confirmation) -> `done` again after that round's review is posted and verified. A declined or deferred post leaves the task `draft`. A PR that the prior-approval gate stops leaves its task unchanged: do not reopen it. PR-mode tasks never sit in `review`, so ledger and body updates during an active PR round need no further confirmation.

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
- ALWAYS keep every finding in the cortex ledger under a stable finding id; NEVER track findings by line number alone
- The cortex ledger is the only cross-round memory
- ALWAYS re-validate open findings against the new code each re-review round; NEVER carry a finding forward on stale evidence
- NEVER report formatting, linter-level, or theoretical concerns in either mode; in STATIC mode report bugs, security issues and logic errors only; in THOROUGH mode every finding carries a category, its cost and a specific suggestion
- ALWAYS pick the review mode before Stage 1: THOROUGH unless the request asks for static mode, and send the critics that mode's criteria
- Verify findings against relevant source context, callers/contracts, and tests; expand reads when needed, not merely to satisfy a stage.
- Use relevant authorized validation or still-applicable evidence; explicitly report unperformed checks and blockers. Never infer test success from missing counts or an unverified claim.
- Label multi-model validation only when the fixed distinct-model quorum is met; preserve directly supported issues with an honest degraded/unfiltered label when consensus is unavailable.
- If no real issues found, output PASS with empty sections
- Keep each finding to one short paragraph: what breaks or what it costs, then the fix. The evidence lives in the review's work, not in a quote trail appended to every comment
- In any Shuttle or GitHub draft, write like a colleague: plain sentences, no headings, no section padding, brief by default
- When the request says to hand the review to Shuttle, end Stage 6 with `shuttle_review_draft` per its SHUTTLE HANDOFF paragraph; NEVER also build or post a GitHub payload
- NEVER wait for an automated reviewer; deduplicate against what it has posted at Stage 1 and once more just before the Shuttle handoff
- Read PR source from the pinned head ref, not the checkout's files; load AGENTS.md, matching specialists and, in THOROUGH mode, past incidents before looking for findings
- Skip checklist dimensions that don't apply
- ALWAYS check that every behavior and construct the PR adds is earned by its stated intent: raise unrequested behavior and needless machinery as THOROUGH findings, and name unrequested behavior in the For-you section in both modes
- ALWAYS answer the intent and worth step in a "For you" section, as the Stage 5 template's labelled list (What, Why, How, Extra, Should we, Lean, Unverified, Before merge, Ask the author) and never as paragraphs, that reaches the user and is never posted: Shuttle `notes` when available, else the top of the final answer; the Cortex body; Stage 6's PRESENT. It never changes the verdict
- No filler or preamble; write the summary and every comment per the Agent Protocol's Writing for people
