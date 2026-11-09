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

Target: GitHub PRs (default flow below; re-reviews follow `references/re-review.md`). Each PR persists to one cortex review task.

## Files and when to read them

This file holds what every review needs: the modes, Stages 1 to 5, and Stage 6's drafting steps. Paths below are relative to this skill's directory. Read a reference file in full when its condition holds, and only then:

| Read | When |
|---|---|
| `references/criteria-thorough.md` or `references/criteria-static.md` (the review mode's file) | before the Stage 2 pre-filter; the same file goes in the Stage 3 critic brief as written |
| `references/cortex.md` | Cortex persistence is in scope, that is, unless the request is answer-only |
| `references/finish-shuttle.md` | the request says to hand the review to Shuttle with `shuttle_review_draft`, after Stage 6 steps 1 to 4 |
| `references/finish-github.md` | any other GitHub PR review, after Stage 6 steps 1 to 4 |
| `references/re-review.md` | the user asks to re-review a PR or check its fixes, the PR already has a `PR Review #<number>:` Cortex task, or the prior-approval gate or `references/batch.md` sends the review there |
| `references/batch.md` and `references/batch-reviewer-task.md` | the request names two or more PRs |

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
3. `APPROVED` at an older commit: compare the PR's own patch then and now. `git diff <base-oid>...<approved-commit> | git patch-id --stable` and the same for the head give equal ids when only the base moved (a rebase); fetch the approved commit by SHA if it is not local. Equal ids: STOP as in step 2 and say the patch is unchanged since the approval. Different ids, or no comparison possible: review only what changed since the approval (`git range-diff <base-oid> <approved-commit> <head>`), through `references/re-review.md` when a review task exists. No new surviving finding means the approval stands: post nothing; if a review task exists, add the round's log line and return it to `done`. Surviving findings go in a Stage 6 draft that carries only those findings, as `COMMENT` or `REQUEST_CHANGES`, never a second `APPROVE`.
4. `DISMISSED`, `CHANGES_REQUESTED`, or no such review: continue normally. A dismissed approval no longer counts on GitHub, so a PASS round still drafts a new `APPROVE`.

For several PRs, follow `references/batch.md`, which runs this gate for each PR before any reviewer starts and lists the skipped PRs with their approval links. Review an approved PR in full only when the user explicitly asks for a fresh review of that PR.

RE-REVIEW FORK: if the user asks to re-review a PR or check its fixes, or the PR already has a `PR Review #<number>:` cortex task, follow `references/re-review.md`; this stage still runs against the new head. To find that task, run `cortex ls --json -l "$LANE" -t pr-review -q "@PR Review #<number>:"` (LANE is the repository directory's name, as `references/cortex.md` step 2 defines it) and keep titles that start with `PR Review #<number>:` (the listing includes `done` tasks).

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

Apply the pre-filter below and deduplicate against applicable comments BEFORE delegation. Verify mechanical facts inline; delegate only unresolved substantial investigations, grouped by shared evidence rather than one child per candidate. Delegate them to the `verifier` agent, which runs on your own model; never to `researcher`, which runs on a cheaper one.

Task-array template (fill in actual revisions, paths, and questions):

```json
{"tasks":[{"agent":"verifier","task":"Verify <screened candidate batch> against <pinned diff/source paths> without edits; trace reachable behavior and relevant tests, returning confidence and file:line evidence."}]}
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

The criteria live in `references/criteria-static.md` and `references/criteria-thorough.md`. Put the review mode's file in the critic brief as written; do not paraphrase it.

Note in the Validation section how many critic sessions were spawned and total findings
evaluated for cost transparency.

### Stage 4: Deduplication

Use the comment snapshot already screened before delegation to make the final deduplication decision. Re-fetch only when relevant comments changed or current coverage is materially required, not simply because this stage was reached.

PR RE-REVIEW: match the reviewer's own prior findings as `references/re-review.md` says before deduplicating against other commenters.

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

Omit empty finding subsections (except for PASS with no findings). Clearly distinguish consensus-filtered findings from directly verified findings whose consensus was unavailable/below quorum. Use `references/cortex.md` for the configured durable product unless the user explicitly requested answer-only/no external records; that mode returns the review inline without Cortex or clipboard writes. For GitHub PRs, the cortex body also carries the findings ledger and round log (defined below), and the review ALWAYS continues to Stage 6 (which drafts nothing when the prior-approval gate says the approval stands).

- Copy to clipboard only within the requested output scope and when the capability is available.

#### Findings ledger and round log

Every PR review body, round 1 included, carries the findings ledger and round log below. The `github thread` column holds each finding's posted comment URL (`body` when raised only in the review body; `-` until posted). Round-log lines record head, mode, verdict, event, and review URL.

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

Matching and porting findings across rounds are in `references/re-review.md`.

### Stage 6: GitHub review draft, approval, and posting

This is the FINAL step of every GitHub PR review and re-review round, including PASS (an `APPROVE` review with no inline comments), unless the Stage 1 prior-approval gate found that the posting identity's approval stands; then nothing is drafted or posted. Nothing is written to the PR until the user explicitly approves the exact draft presented. In explicit answer-only mode, present the draft inline and stop: posting and Cortex close-out are external records.

How the review ends depends on the request. Run steps 1 to 4 below in every PR review. Then, when the request tells you to hand the review to Shuttle with `shuttle_review_draft`, follow `references/finish-shuttle.md`; otherwise follow `references/finish-github.md`, steps 5 to 10.

1. SELECT: one inline comment per surviving finding (CERTAIN/LIKELY; consensus-filtered, or labeled not consensus-filtered), anchored on lines the PR changed at the pinned head (`side: "RIGHT"`; add `start_line` + `start_side` for ranges). Findings without a changed-line anchor (unchanged code, whole-PR concerns) go in the review body. Filtered findings never appear; praise stays to one line in the body. Start each nit's comment with `Nit:` so the author knows it is optional. Fewer, better comments.
2. ANCHOR CHECK: from the pinned revision-scoped diff, confirm every `line`/`start_line` falls on the new side of one hunk of that file (added or context line; a range stays within one hunk) and that the source line there is the code the finding describes. A single out-of-diff line makes GitHub reject the whole review (422).
3. WRITE brief: the review body is 2-4 plain sentences -- what the PR does, the verdict, and the findings that matter most. Each inline comment is ONE short paragraph of at most three sentences: what is wrong, what it costs, and the fix. Quote code only when the problem is not visible in the diff hunk the comment sits on; never attach validation logs, checklists, critic tallies or praise padding to the draft. Polite, specific, first person, written like a colleague leaving a GitHub review. No internal jargon in public text (F-ids, critic tallies, cortex references) and no tracking params (`?utm_source=`).
4. RECOMMEND the event from the verdict; the user makes the final call:
   - PASS -> `APPROVE` (body only)
   - GO WITH FIXES -> `APPROVE` with the non-blocking comments, or `COMMENT`
   - NEEDS REVIEW -> `COMMENT`
   - BLOCK -> `REQUEST_CHANGES`

   Prefer `COMMENT` over `REQUEST_CHANGES` when the decisive findings are documentation-only, runtime-unverified, or not consensus-filtered. When the reviewer authored the PR, GitHub accepts only `COMMENT`. Omitting `event` creates a PENDING review the user can finish in the GitHub UI.
## Rules

- NEVER write to the PR (reviews, comments, replies, resolutions, dismissals) without explicit user approval of the exact drafted payload; post ONLY that payload, ONCE, after the Stage 6 pre-post check
- ALWAYS run the Stage 1 prior-approval gate before any analysis, delegation, or Cortex write; the posting identity's approval stands until the PR's own patch changes, and a verdict that has not changed NEVER gets a second review or post
- ALWAYS end a GitHub PR review or re-review round with the Stage 6 draft (an `APPROVE` body for PASS), unless the prior-approval gate says the existing approval stands; verify anchors before presenting and again after posting
- ALWAYS keep every finding in the cortex ledger under a stable finding id; NEVER track findings by line number alone
- The cortex ledger is the only cross-round memory
- NEVER report formatting, linter-level, or theoretical concerns in either mode; in STATIC mode report bugs, security issues and logic errors only; in THOROUGH mode every finding carries a category, its cost and a specific suggestion
- ALWAYS pick the review mode before Stage 1: THOROUGH unless the request asks for static mode, and send the critics that mode's criteria
- Verify findings against relevant source context, callers/contracts, and tests; expand reads when needed, not merely to satisfy a stage.
- Use relevant authorized validation or still-applicable evidence; explicitly report unperformed checks and blockers. Never infer test success from missing counts or an unverified claim.
- Label multi-model validation only when the fixed distinct-model quorum is met; preserve directly supported issues with an honest degraded/unfiltered label when consensus is unavailable.
- If no real issues found, output PASS with empty sections
- Keep each finding to one short paragraph: what breaks or what it costs, then the fix. The evidence lives in the review's work, not in a quote trail appended to every comment
- In any Shuttle or GitHub draft, write like a colleague: plain sentences, no headings, no section padding, brief by default
- NEVER wait for an automated reviewer; deduplicate against what it has posted at Stage 1 and once more just before the Shuttle handoff
- Read PR source from the pinned head ref, not the checkout's files; load AGENTS.md, matching specialists and, in THOROUGH mode, past incidents before looking for findings
- Skip checklist dimensions that don't apply
- ALWAYS check that every behavior and construct the PR adds is earned by its stated intent: raise unrequested behavior and needless machinery as THOROUGH findings, and name unrequested behavior in the For-you section in both modes
- ALWAYS answer the intent and worth step in a "For you" section, as the Stage 5 template's labelled list (What, Why, How, Extra, Should we, Lean, Unverified, Before merge, Ask the author) and never as paragraphs, that reaches the user and is never posted: Shuttle `notes` when available, else the top of the final answer; the Cortex body; Stage 6's PRESENT. It never changes the verdict
- No filler or preamble; write the summary and every comment per the Agent Protocol's Writing for people

## Self-Improvement

Capture feedback only for concrete, novel, reusable evidence from this task and within its authorized scope. Ordinary success or restating existing guidance starts no notes read, observer, or promotion.

When capture is justified, the current agent owns the gate: resolve `SKIP_SKILL_NOTES` from the environment only (never `.env`); `1` or `true` disables notes. Otherwise use the `improve-skills` Fast Loop. Reuse applicable evidence; one owner and at most one entry per skill/session. A delegated observer receives `notes_enabled=true`, the target, and the concrete observation.
