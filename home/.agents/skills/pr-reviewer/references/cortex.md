# Cortex persistence

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
    # write the rendered review markdown to "$REVIEW_BODY" using SKILL.md's Stage 5 template

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

8. PR MODE LIFECYCLE. Status flow: `draft` from `cortex add` through the Stage 6 approval -> `done` once the approved review is posted and verified (`references/finish-github.md` step 10) -> a re-review request reopens `done` -> `draft` (the request IS the explicit confirmation) -> `done` again after that round's review is posted and verified. A declined or deferred post leaves the task `draft`. A PR that the prior-approval gate stops leaves its task unchanged: do not reopen it. PR-mode tasks never sit in `review`, so ledger and body updates during an active PR round need no further confirmation.

9. SHUTTLE REVIEWS: write Cortex once per round, after `shuttle_review_draft` (`references/finish-shuttle.md` step 4), never earlier in the review. Render the body with its round-log line already ending "handed to Shuttle", then make ONE codemode call that does steps 4 and 5 together: `tools.bash` for `cortex add ... --json` (on a re-review, the body edit of the existing task instead), then `tools.cortex_update` with the returned id and the verdict. Where `cortex` is not on PATH, as in a remote sandbox, run it through the host bridge named by `host_bridge` in the skill's `private/forges.json` and pipe the body on stdin: `cat <body file> | <host bridge> cortex add "<title>" --lane=<lane> --status=draft --bodyFile=/dev/stdin -t pr-review --json` (call `cortex` itself, not through `sh -c`, which the host may hold for approval). Without codemode, put the two calls in one message only when the task id is already known; otherwise make them one after the other. Shuttle's cleanup turn closes the task (`references/finish-shuttle.md` step 5).

## Output

- For authorized durable output, persist the review per the recipe above (repo lane, `draft`, `pr-review` plus supplied-plan tags except reserved `plan`); leave priority unset unless explicitly requested.
- Report the created task ID only after persistence succeeds; its body is viewable via `cortex show <review-id>`. For explicit answer-only mode, return the structured review inline instead.

Everything in this file applies to authorized durable output, not explicit answer-only mode.
