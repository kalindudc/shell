# Briefs, spawning and steering

## Spawning

- Use the `spawn` tool for members in the lead's project, with a persona on every task (`delegation` explains the models). Leave persona and model unset only for work that needs the lead's judgment, and say why in the task.
- Give a member that edits code its own worktree (`environment: "worktree"`). Never let two members edit the same working tree.
- For a permanent member, spawn it, then set the agreed mode before its first wake loop, for example `bb thread update <id> --parent-notifications stuck`. If no persona fits a cheap watcher, set a cheaper `model` on the task.
- If the `spawn` tool isn't available, use `bb thread spawn` below for every member, passing the agreed `--parent-notifications` at spawn.
- Use `bb thread spawn` when a member needs another project, a remote machine or a specific provider, for example:
  `bb thread spawn --project <id> --parent-self --parent-notifications auto --title "<short name>" --provider <provider> --model <model> --prompt-file <brief>`
  Add `--new-environment worktree` for code edits, or the machine and environment-provider flags from that provider's skill. Pass `--provider` together with `--model` when you override the model.
- Before spawning, check the roster in `LEAD.md` and the live threads. If a member already holds the topic, send it the work instead.

## Task brief template

Put shared context in a file and keep the task message short: "Read `<FLEET>/briefs/<file>.md` and do exactly what it says. Your slice: <items>." These templates assume the member shares the lead's machine. For a remote member, paste the brief and rules into its prompt and name its return path (`fleet-files.md`).

```markdown
# <Job>: <one line>

FLEET=<absolute path>. Read $FLEET/RULES.md first. Lead thread: <id>. Report as the end of this brief says.

## Why
<One paragraph: the goal, and the decision this result feeds.>

## Inputs
- Reuse: <files>, if under <N> hours old. Re-check anything older or odd.
- Leads only, re-derive before use: <old notes, earlier threads>.

## Checks
1. <Question or check, with the exact source to read.>
2. <...> For anything new replacing something old: what is different, and what limits does the new
   path enforce that the old one didn't?

## Output
Write $FLEET/<stream>/<file> with these fields: <schema>.
Every fact has a matching entry in `claims`: {claim, command_or_source, output_excerpt, checked_at_utc}.
If you couldn't check something, write "not verified" and why.

## Final answer
Under 3,000 characters: the answer first, one line per item, the files you wrote, and only the questions
the human must answer. If the job is long, send each verified piece to the lead as soon as it's ready.

## Non-scope
Read-only unless stated. <What not to touch.> Budget: about <N> tool calls.
```

For a change to something the human already uses, add a Keep section (the parts the human relies on, which must survive) and a Proof section (before and after screenshots or diffs), and say "local only until approved". A brief that says "rework completely" invites a rebuild that throws away what the human relied on.

## Permanent member prompt

```text
You are the permanent <role> for lead thread <id>. You run for days on scheduled wake-ups.

Read in full before anything else:
1. <FLEET>/RULES.md
2. <FLEET>/<area>/CHARTER.md: what you own, what to report, cadence. It is the source of truth and the
   lead may edit it. Re-read it at the start of every wake.
3. <FLEET>/<area>/state.json: your cursors and memory. Keep all state there, so a compaction loses nothing.

Now: follow <FLEET>/<area>/CHECK.md once. On this first run, <start cursors at now and report nothing older |
send one short digest of the last N days, then start cursors at now>. Then schedule your next wake-up per
the charter and end your turn with one line.

Reporting: your parent notifications are set to <stuck: your final answers do NOT reach the lead |
auto: your final answers reach the lead, so keep empty ones to one line>. When something is material,
report with `timeout 50 bb thread tell <lead> --message-file - <<'EOF'` ... `EOF`. <Push to the human
only for: ...>. Never send acknowledgements. When the lead messages you, update the charter or state and
carry on. When the lead says pause, set "paused" in your state file, cancel your own wake-ups and queued
actions, confirm, and wait for an explicit resume. When the lead retires you, cancel your wake-ups and confirm.
```

## Steering a running member

Start messages with "Lead:", quote the human's words when relaying a correction, and say exactly what to change and what to report back, for example "Amend the single commit, re-validate, and send me the new head sha." For a rule that affects everyone, send the same message to every live member and add the rule to `RULES.md`.

To pause or replace a member, follow the pause steps in `SKILL.md`: the member cancels its own wake-ups and confirms, because `bb thread stop` doesn't cancel them. Ask for a confirmation only for these transitions, not for routine messages.

## Critic brief

Use for a high-risk change, a plan, or anything where being wrong is expensive. Run three critics on three model families (`critique` has the models), with the same brief, independently.

```markdown
# Critic brief: <change> at <revision>

You are one of three independent critics, each on a different model. Try to break this before
<the human> decides. Read-only: no comments, no edits, no dry runs that reach a live system.

Read first: RULES.md (change risk, mitigate first), <the change>, <evidence files>, <the pre-mortem>.

Check:
1. <What it really produces, compared with what was intended.>
2. <Defaults it meets or resets, targets it lands on, limits and quotas.>
3. <Load, failure and rollback behaviour.>
4. <Detection: how we'd notice it going wrong.>

For each finding: what's wrong, evidence you checked yourself, severity (blocker, major or minor) and the fix.
Then a verdict in two sentences: ship as is, ship with fixes, or don't ship.
Write <path>/critics/<model>.md, then reply in under 1,000 characters with your verdict and any blocker or major findings.
```

Consolidate the reports into one table for the human: critic, verdict, main finding, and how many critics raised each point. Agreement is context, not a vote: one critic's verified blocker still blocks. After fixes, run a second pass on the revised revision that marks each earlier finding fixed, partly fixed or not fixed, with evidence, and checks for regressions. Record who waived anything left open.

## Phase pipeline for large batches

For a batch of similar items, such as dozens of hosts, services or teams, run phases with a file between each:

1. Inventory: one researcher builds the list from live sources, with method notes.
2. Deep checks: several researchers, one slice each, share a common brief and write one evidence file per item.
3. Score: a classifier or rubric sorts the items, for example "we can do it safely", "the owner must decide" and "leave out".
4. Build: builders draft only the confident items.
5. Verify: a verifier on a different model re-checks each item's evidence and each draft.
6. Write: one review document for the human with the decisions they need to make.
7. Verify the claims in anything that will be sent to other people.
8. The human reviews. Only then is anything sent or saved under the human's name.

Scale it to the batch. For a handful of items, one researcher can inventory and check, and the lead can write the review. Keep the independent verifier whenever results go to other people.

Archive each phase's members once their files are read. A sub-lead can own phases 2 to 7 for a batch handed to other teams (`members.md`). Before contacting a team, reconcile everything for that team: live inventory, ownership, earlier messages and drafts, their replies, and work they already have in progress. Then send one complete packet per team, so the same people aren't asked twice.

## Retro brief

When something goes wrong, spawn a read-only retro member once things are stable. Ask for a timeline with sources, where the time went, five whys across technical, design, process and agent causes, what went well, corrections to the brief's own claims, and concrete rule changes for `RULES.md`. Include the human's takeaway and check it against the record. Give it the evidence collected during the incident (`risk.md`).
