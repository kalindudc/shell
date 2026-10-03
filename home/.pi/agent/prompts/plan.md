---
description: Creates a structured plan for implementing a vertical slice of working software, reviewed before it is saved
---

Load the `cortex-planner` skill and follow its instructions to create a comprehensive plan for: $ARGUMENTS

## Review before saving

A plan is complete only after its review. Run this cycle on the plan tmpfile after the skill's Post-Write Review and before its `cortex add`, and save the plan once, when the cycle ends. Each step is one batched tool call.

1. Switches. Run this once. It prints only these two keys, from the environment first and `~/.env` second. NEVER print the rest of `~/.env`: it holds secrets. Unless SKIP_CRITIQUE is on, `cat ~/.agents/skills/critique/critics.yml ~/.agents/skills/critique/critic-prompt.md` in the same call.
   `for k in SKIP_PLAN_REVIEW SKIP_CRITIQUE; do v=$(printenv "$k"); [ -n "$v" ] || v=$(sed -n -E "s/^(export )?$k=[\"']?([^\"']*)[\"']?\$/\2/p" ~/.env 2>/dev/null | tail -1); echo "$k=$v"; done`
   `1` or `true` turns a switch on. SKIP_PLAN_REVIEW skips this whole cycle; SKIP_CRITIQUE skips step 3.
2. Review. Spawn one `researcher` with the review brief below. Give it the tmpfile path and the repo root, not the plan text.
3. Critics. Number every review finding and every design claim in Verification Notes, each claim with the reviewer's verdict. Send them in ONE `spawn` call: one task per model in `critics.yml`, with `model` set and no agent name, each carrying the critic prompt, the critic criteria below and the tmpfile path. An item is kept when at least max(2, floor(N/2)+1) critics vote KEEP. Skip this step when there is nothing to vote on. When SKIP_CRITIQUE is on or fewer than two critics return, keep only the review findings whose evidence you confirm, marked "not consensus-filtered".
4. Fix. Apply every kept item in one rewrite of the tmpfile. Add one Verification Notes line: rounds run, items kept and fixed, items rejected, which critics voted, or which switch skipped a stage.
5. Repeat steps 2 to 4 once, only if a kept item was a Blocker, using the second-round brief. NEVER start a third round: list anything still kept as unresolved in Verification Notes and in your reply.

Then run `cortex add` and post the skill's attribution update, with the review result in that same message. If the review spawn fails, stop and tell the user. Do not save an unreviewed plan unless SKIP_PLAN_REVIEW is on.

## Review brief

"Review the implementation plan at <tmpfile> against the repository at <root>. Do not edit anything. Answer each question with file:line or command evidence:
1. Does every FROM block appear exactly once in its target file, and does every UPDATE target exist or come from an earlier CREATE in the plan?
2. Do the plan's claims about external tools, flags, versions and APIs hold? Probe them with --help, a version check or the source.
3. For each design claim in Verification Notes: Supported or Refuted?
4. Is every Mid-Level Objective achieved by some task, and can every task's Verify line actually be run or observed?
5. What is the most likely way this plan fails during implementation?
Report only Blockers (the plan cannot work as written) and Concerns (it works but forces a deviation), each with its evidence and a one-line fix, at most 8. A stale detail in an informational section is not a finding. No findings is a valid answer."

Second round: replace questions 1 to 5 with "Check only the fixes for items <ids> in tasks <numbers>, and report only problems those fixes introduced."

## Critic criteria

KEEP when the item is verified against the files or a probe, would make the plan fail or force a deviation, and has the right severity. For a design claim, KEEP means the claim is wrong in a way that matters. REJECT when the item is speculative, contradicted by the source, a matter of style, or already handled by the plan.

## Rules

- **ALWAYS** load the `cortex-planner` skill first for detailed instructions
- **ALWAYS** verify source files exist before reading
- **ALWAYS** use actual code and tests as source material
- **NEVER** invent or hallucinate code behavior
- **NEVER** exceed 128 characters for output filename
