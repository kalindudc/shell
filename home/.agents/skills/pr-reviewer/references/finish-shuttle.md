# Finish: hand the review to Shuttle

Read this when the request tells you to hand the review to Shuttle with `shuttle_review_draft`. Shuttle shows the draft to the user and posts it, so Stage 6 changes: run Stage 6 steps 1 to 4 in SKILL.md (SELECT, ANCHOR CHECK, WRITE, RECOMMEND), then the steps below. Skip `references/finish-github.md`: build no payload file and post nothing.

1. NOTES: the "For you" section goes in `shuttle_review_draft`'s `notes`, as the labelled list from the Stage 5 template without its heading, never as paragraphs: Shuttle shows it above the draft and never posts it. If the tool has no `notes` field (an older Shuttle), open your final answer with it instead, under the heading "For you (not posted)". NEVER put it in `summary` or a finding.
2. LAST DEDUP: just before the call, re-fetch the PR's review comments once and drop or merge any finding that a comment posted since Stage 1 already raises; automated reviewers often finish after you start. Do not wait for more comments.
3. CALL `shuttle_review_draft` once: the review body as `summary`; the recommended event as `verdict` (APPROVE is approve, COMMENT is comment, REQUEST_CHANGES is changes); and one finding per inline comment with `severity` (Critical is high, Medium is medium, Minor is low, Nit is nit), `path`, the anchored `line` and the comment as `body`. A finding about a whole file goes in without `line`; a whole-PR finding stays in `summary`.
   When the tool offers them (Shuttle's auto post reads them), also give each finding `consensus` as its Stage 3 votes, `{keep, total}` with KEEP votes out of the critics that voted (leave it out when consensus was unavailable or below quorum, never invent votes); `evidence` as up to five decisive excerpts `{path, from, to, quote}` copied exactly from the pinned head, the lines the finding's verification read; and `category` as one or two words.
   Give `assessment` once for the whole PR: `risk` (low, medium or high) and `concerns`, the PR-level points a line comment cannot carry, each as `{kind, text}` with the kind that fits best: `description` (the description claims what the diff does not do, or leaves out what it does), `scope` (unrelated files, tests changed to pass, generated churn), `unverified` (a claim or result you could not check or run), `process` (CI, approvals, conflicts, rebase or merge state), `design` (a behaviour or design point the user should weigh) or `other`. Shuttle's auto post holds drafts by kind, so pick the kind honestly rather than to pass or fail it; empty when there are none.
4. CORTEX: leave the Cortex task `draft`, with a round-log line ending "handed to Shuttle".

The draft the user sees is the notes, the summary and the inline comments, nothing else: the ledger, checklist, validation log and filtered-findings list stay in the Cortex body and NEVER appear in the draft.

## Rules

- When the request says to hand the review to Shuttle, end Stage 6 with `shuttle_review_draft` per this file; NEVER also build or post a GitHub payload
