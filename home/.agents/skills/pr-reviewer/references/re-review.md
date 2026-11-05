# PR re-review rounds

MODE TRIGGER: the user asks to re-review a PR or check the author's fixes, or the PR already has a `PR Review #<number>:` cortex task. One review task per PR: its body is the findings ledger and the ONLY cross-round memory. Locating that task by PR number is not plan discovery -- plans are still linked only when the user names one. The Stage 1 prior-approval gate runs before this section and can end the round before step 1.

LEDGER: every PR review body, round 1 included, carries the findings ledger and round log that SKILL.md's Stage 5 defines.

How findings carry across rounds:

- Matching across rounds: match on the issue's ESSENCE -- category + the offending code pattern -- NEVER on line numbers (SARIF fingerprints: identity must be "resistant to changes... such as the line number").
- Porting rule (Gerrit): carry ONLY `open` findings into a new round; recompute the anchor; degrade line -> file-level -> review body. `fixed`/`wontfix` are never carried.

PR RE-REVIEW: the reviewer's own prior-round comments (the ledger's `github thread` URLs) are NOT duplicates to drop -- they are the prior findings under re-validation. A candidate matching an existing `open` finding (same essence -- category + offending code pattern, never line numbers) IS that finding -- re-anchor and continue it under its F-id instead of creating a new one. A candidate matching a `fixed`/`wontfix` entry is a regression or repeat -- name its F-id explicitly instead of minting a fresh finding. Comments from everyone else are deduplicated as SKILL.md's Stage 4 says.

1. LOCATE: `cortex ls --json -l "$LANE" -t pr-review -q "@PR Review #<number>:"`, keeping titles that start with `PR Review #<number>:` (the listing includes `done` tasks). Exactly one -> use it; none -> run a first review; several -> ask once. The re-review request IS the explicit confirmation to reopen it: `cortex_update` with status `draft` and a `round <N> @<new-head>` message.
2. FETCH: run Stage 1 against the new head, and read the prior rounds' threads (the ledger's `github thread` URLs) from the full-schema comments endpoint (`gh api --method GET repos/<owner>/<repo>/pulls/<n>/comments --paginate`; not `GET .../reviews/<review-id>/comments`, whose legacy schema returns null `line`/`side`), replies included. Author replies ("fixed in X", "intentional", disagreement) feed step 3. A null `position` marks an outdated thread whose code changed.
3. RE-VALIDATE every `open` finding against the new head as a full re-check with fresh evidence -- NEVER carry-over: `fixed` (record the fixing commit), still present (re-verify the failure path, re-anchor at the current line), `outdated` (the referenced code is gone), or `wontfix` (the user accepts the author's rationale). Weigh author pushback on its merits: withdraw the finding with the reason when the pushback holds; otherwise keep it and surface the disagreement to the user.
4. NEW CHANGES: review the commits since the last reviewed head (`gh api --method GET repos/<owner>/<repo>/compare/<old-head>...<new-head>`, `git diff` when objects are local, or the full PR diff when the old head was force-pushed away) through Stages 2-4 with full-PR context. A candidate matching a ledger finding's essence IS that finding. Send only new or changed findings to Stage 3; reuse prior critic consensus when a finding and its code region are unchanged.
5. OUTPUT: update the same task body (this round's review template, ledger statuses and locations, round log) via anchor-based edits or a `--body-file` rewrite. Redo the "For you" section only when the description, linked issues or scope changed since the last round, and otherwise say it is unchanged since that round.
6. NEW GITHUB REVIEW through Stage 6, unless the prior-approval gate says the posting identity's approval stands; NEVER edit, dismiss, resolve, or reply to prior reviews or threads unless the user explicitly asks. The body lists fixed findings (with fixing commits), still-present findings (linking their existing threads), and new findings. Inline comments go to new findings and to still-present findings whose prior thread is outdated (re-anchored, linking the prior thread); a still-present finding with a live thread is referenced in the body only, to avoid duplicate threads. Recommend the event from the round verdict (e.g. every finding fixed -> `APPROVE`). Approval, pre-post check, posting, verification, and close-out to `done` follow Stage 6 unchanged.

## Rules

- When a PR re-review round posts, ALWAYS post a NEW GitHub review; NEVER edit, dismiss, resolve, or reply to prior reviews or threads unless the user explicitly asks
- ALWAYS re-validate open findings against the new code each re-review round; NEVER carry a finding forward on stale evidence
