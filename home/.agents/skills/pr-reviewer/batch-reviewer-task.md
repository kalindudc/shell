# Batch reviewer task template

Used by `Batch PR reviews` in `SKILL.md`. The parent fills every `{placeholder}`, picks exactly one mode block, one scope block and one source block, and sends the result as one minion task per PR. Do not otherwise edit the wording: every PR in every batch gets the same instructions, so verdicts stay comparable.

Placeholders are the lower-case `{names}` below; every other brace (the JSON shapes in the Files section) is literal text.

- From `gh pr view`: `{owner}`, `{repo}`, `{number}`, `{title}`, `{author}`, `{additions}`, `{deletions}`, `{changed_files}`, `{url}`, `{base_branch}`, `{base_oid}`, `{head_oid}`.
- From batch setup: `{head_ref}` (the verified `refs/pr-review/<n>-<head12>`), `{clone}`, `{out_dir}` (`<storage>/pr-reviews/pr<n>`), `{skill_path}` (this skill's `SKILL.md`), `{tooling_note}`, `{mode_block}`, `{scope_block}`, `{source_block}`.
- `{risk_areas}`: one or two sentences naming what could break for this kind of change, taken from the title and description. Never a suspected finding.
- STACKED: `{lower_pr}`. RE-REVIEW: `{round}`, `{task_id}`, `{old_head}`, `{old_base}`, `{old_ref}`, `{ledger_summary}` (each ledger row with its status, location, one-line summary and thread URL, plus filtered items from earlier rounds). DELTA: `{approved_commit}`, `{approval_url}`.

## Mode blocks

- FIRST: `FIRST REVIEW against base branch {base_branch}.`
- STACKED: `FIRST REVIEW of a STACKED PR: its base is the head of #{lower_pr} ({base_branch}), not the default branch. Review only base..head. Read the lower PRs' code for context, but report their issues only when this PR makes them newly reachable.`
- RE-REVIEW: `RE-REVIEW, round {round}. Follow the skill's 'PR re-review rounds' steps 2 to 4 only (no Cortex writes). Read the prior task read-only with: cortex show {task_id} --json | jq -r .task.body. The last round reviewed head {old_head} on base {old_base} (local ref {old_ref}; NOT the current head). Changes since then: git -C {clone} range-diff {old_base}..{old_head} {base_oid}..{head_oid}. Prior ledger, with thread URLs: {ledger_summary}. Re-validate every open finding with fresh evidence at this head and read the replies on its thread. Do not re-raise filtered or wontfix items unless the new code changes them materially.`
- DELTA: `DELTA REVIEW since the posting identity's approval at {approved_commit} ({approval_url}). Review only what changed since then: git -C {clone} range-diff {base_oid} {approved_commit} {head_oid}. Report only new findings in the changed code; the approval otherwise stands, so a clean result is PASS with nothing to post.`

## Scope blocks

Pick the block for the batch's review mode (see the skill's `Review modes`); every PR in a batch gets the same one.

- THOROUGH: `THOROUGH review. Report bugs, security issues and logic errors introduced by this PR, then work through the Stage 2 THOROUGH dimensions in order (design, tests, error handling and operability, performance, compatibility, maintainability and readability, documentation). Give every candidate its category, its cost and a specific suggestion; nits are allowed with severity nit. Each candidate needs CERTAIN or LIKELY confidence and file:line evidence with short verbatim quotes; a bug also needs a traced, reachable failure path. Drop anything weaker, and anything Stage 2 says not to report in either mode.`
- STATIC: `STATIC review. Report only bugs, security issues and logic errors introduced by this PR. Each candidate needs CERTAIN or LIKELY confidence, file:line evidence with short verbatim quotes, and a traced, reachable failure path; drop anything weaker.`

## Source blocks

- CLONE: `The local clone at {clone} has both pinned commits. Read with git -C {clone} show <sha>:<path>, git -C {clone} diff {base_oid} {head_oid} and git -C {clone} grep <pattern> <sha> -- <paths>. NEVER check out, switch, reset, stash, commit, fetch or edit files in that clone; its working tree belongs to the user. To execute code, create a detached worktree with git -C {clone} worktree add --detach {out_dir}/worktree {head_oid}, run there, and remove it with git -C {clone} worktree remove --force {out_dir}/worktree when finished. No package installs, image pulls or downloads. {tooling_note}`
- GH-ONLY: `There is no local clone; do not create one. Read the diff with gh pr diff {number} -R {owner}/{repo} and files with gh api --method GET 'repos/{owner}/{repo}/contents/<path>?ref=<sha>' --jq .content | base64 -d. Report every check you could not execute.`

`{tooling_note}` names the runtimes known to be present or absent on the host (for example "OpenResty resty is absent; LuaJIT, busted and Go are present"), so reviewers do not each rediscover them.

## Task

```text
You are an independent code reviewer for GitHub PR {owner}/{repo}#{number} "{title}" by {author} ({additions} additions, {deletions} deletions, {changed_files} files). URL: {url}
Pinned base: {base_oid}
Pinned head: {head_oid} (local ref {head_ref})
Mode: {mode_block}

## What to do
Read the pr-reviewer skill at {skill_path} in full first. Run its Stage 1, Stage 2 and Stage 4, plus Stage 5's validation and output template. Your parent coordinates a batch review and set these overrides, which take priority over the skill:
1. Do NOT run Stage 3 critic consensus and do NOT spawn minions. The parent runs one critic round across every PR in the batch.
2. Do NOT write to Cortex, the clipboard or GitHub: no reviews, comments, replies or reactions. GitHub calls stay read-only: gh pr view, gh pr diff, gh pr checks, gh run view, and gh api --method GET. The parent already ran the prior-approval gate; do not run it again.
3. Do NOT assemble or post the Stage 6 payload. DO run Stage 6's ANCHOR CHECK for every candidate: the line (and start_line, if any) must fall on the new (RIGHT) side of a single hunk in git diff {base_oid} {head_oid} -- <path>, and the source line there must be the code the finding describes.
4. Source: {source_block}
5. Scope: {scope_block} Zero candidates is a valid result. List concerns you checked and rejected in the review's Filtered section, each with its evidence.
6. Risk areas to check first. These are pointers, not conclusions: {risk_areas}
7. Deduplicate against every existing inline comment, review and issue comment on the PR (all pages) before listing a candidate.

## Files to write in {out_dir}/
- review.md: the skill's Stage 5 review template with "Critic consensus: pending" on each finding; Validation (every command you ran and its result, including gh pr checks {number} -R {owner}/{repo}); Checklist; Coverage (files in the diff versus files examined, naming each skipped file and why); then the Findings ledger table with its github thread column ("-" for new findings) and one Round log line for this round ending "not posted".
- candidates.json: {"candidates": [...], "prior_findings": [...]}. Each candidate has id ("C1", "C2", ...), severity (critical, medium or minor; nit in a THOROUGH review), category (THOROUGH only: bug, security, design, tests, operability, performance, compatibility, maintainability or docs), confidence (CERTAIN or LIKELY), title, path, line, optional start_line, anchor_verified (true or false), evidence (file:line references with short verbatim quotes), impact, suggestion, and dedup ("none" or the URL of the comment it overlaps). prior_findings lists re-validated ledger findings as {id, status (open, fixed, outdated or wontfix), evidence, fixing_commit}; it is empty for a first review.
- comment-C<k>.md for each candidate: the public inline comment, in a polite first person. Explain why it breaks or what it costs, give the evidence and suggest a fix. Start a nit's comment with "Nit:". No internal jargon (candidate ids, critic tallies, Cortex references) and no tracking parameters in links.
- body.md: the draft public GitHub review body. Say what you found, what is verified versus unverified, and what you ask of the author. Describe CI only as of the time you checked it.

## Final answer
Keep it under 3,500 characters, because longer reports are truncated. Include, in this order: the PR number, pinned head and whether the live head still matches it; the mode and scope (THOROUGH or STATIC); the provisional verdict (PASS, GO WITH FIXES, NEEDS REVIEW or BLOCK); one line per candidate (id, severity, confidence, path:line, title); prior-finding statuses for a re-review; CI status in one line; the validation you ran and what you could not run; coverage counts (files in the diff versus examined); and the output directory. Nothing else.
```
