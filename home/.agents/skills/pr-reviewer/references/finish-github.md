# Finish: draft, approve and post a GitHub review

Read this for a GitHub PR review that does not end in a Shuttle handoff, after Stage 6 steps 1 to 4 in SKILL.md (SELECT, ANCHOR CHECK, WRITE, RECOMMEND), and for each PR of a batch. Nothing is written to the PR until the user explicitly approves the exact draft presented.

5. BUILD: write each body to its own markdown file in a scratch directory (e.g. `/tmp/pr<n>-review/`) and assemble the payload with `jq` -- NEVER hand-escape JSON -- pinned to the reviewed head:
   ```bash
   jq -n --arg commit_id "$HEAD_SHA" --arg event COMMENT \
     --rawfile body body.md --rawfile c1 comment-1.md \
     '{commit_id: $commit_id, event: $event, body: $body,
       comments: [{path: "<path>", start_line: 10, start_side: "RIGHT", line: 12, side: "RIGHT", body: $c1}]}' \
     > github-review-draft.json
   ```
   Validate before presenting: `jq` parses the file and `grep -c utm_` returns 0.

   The summary ALWAYS travels as this payload's `body`, next to its `event`, so the verdict and its explanation are ONE review. GitHub shows an approval with a body as "<login> approved these changes" with the body in a nested "<login> left a comment" card; that card is part of the review, not a separate comment. NEVER post the summary as an issue comment, or as a second review next to a body-less approval.
6. PRESENT for approval: first the "For you" section, labelled as not part of the payload, then the exact review body, each inline comment with `path:line(s)`, the recommended event and alternatives, the payload path, the posting identity (`gh api --method GET user --jq .login`), and the post command. STOP and wait. Requested edits -> revise, repeat steps 2, 3 and 5 (ANCHOR CHECK, WRITE, BUILD), and re-present. Approval of the draft as presented (e.g. "post it") authorizes exactly that payload and event; naming a different event (e.g. "request changes") changes only `event`.
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

## Output

- For GitHub PRs, finish by presenting the Stage 6 draft for approval, or by reporting that the prior-approval gate skipped the PR and why; after an approved post, report the review URL, event, and verified anchors, and the closed-out task ID.

## Rules

- ALWAYS send the summary as the `body` of the same review that carries the `event`; NEVER as a separate issue comment or a second review
- ALWAYS close out the cortex review task (`done`) only after the posted review is verified; leave it `draft` when posting is declined or deferred
