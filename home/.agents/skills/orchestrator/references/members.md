# Permanent members, wake-ups and sub-leads

A permanent member runs for days. It must survive compaction, restarts, failed turns and changes of direction. Build it from three files and one loop.

## The three files

1. Charter (`<area>/CHARTER.md`): what it owns, its sources, what to report and what not to, cadence and reporting. The lead edits it and the member re-reads it every wake. Keep it to the current truth. Put a dated change at the top while it's fresh, then fold it into the body. A long charter full of dated notes contradicts itself.
2. Check prompt (`<area>/CHECK.md`): the exact steps of one wake, so the wake-up prompt stays one line ("Follow <FLEET>/watch/CHECK.md").
3. State file (`<area>/state.json`): cursors, what's already been reported, and the health of each loop. Write the whole file at once (`cat > file <<'EOF'`), check it with `jq . file`, and advance cursors only when every read in the check succeeded.

Charter skeleton:

```markdown
# <Role> charter (permanent member of lead thread <id>)
Read <FLEET>/RULES.md first. Re-read this file every wake. The lead may edit it.

## Changes
- <date>: <what changed, folded into the body once settled>.

## What you own
## Sources
<Each channel, thread, PR list or system to read, with ids and the read-only tool to use.>
## Report
<What counts as material. What never to report.>
## Cadence
<Times and time zone. Change windows. Weekends.>
## Reporting
<Route to the lead, push rules and title prefixes, notification mode.>
```

Check prompt skeleton:

```markdown
# One check
1. Run ListWakeups. Re-read RULES.md, CHARTER.md and state.json.
2. Read every source since its cursor, in parallel where possible.
3. If any read failed: don't advance its cursor, record the error in state.loops.<name>.last_error,
   and tell the lead once if it keeps failing.
4. Report what's new and material (see Reporting), skipping anything in state.already_told.
5. Write state.json: cursors, already_told and last_ok_utc for each loop that succeeded.
6. If state.paused is true, stop here without scheduling, and end with one line.
7. Schedule the next wake-up with the one-line prompt "Follow <FLEET>/<area>/CHECK.md". Then record the
   returned id and time as next_wake_id and next_wake_utc. If scheduling failed, clear them and tell the lead.
8. End with one line.
```

State skeleton:

```json
{
  "cursors": {"<channel or thread id>": "<last seen timestamp>"},
  "already_told": ["<short key per reported item>"],
  "loops": {"main": {"last_ok_utc": "", "next_wake_utc": "", "next_wake_id": "", "last_error": null}},
  "window": null,
  "paused": false
}
```

On the first run, start cursors at now and report nothing older, unless the charter asks for a one-time digest of recent history. Read chat and other systems with the read-only tools the harness provides (search for them, for example `searchTools("slack")` in codemode). Observation is read-only. Any write a member makes needs a standing permission in `RULES.md` or the gate.

## The loop

- Keep exactly one pending wake-up per loop. A member with two loops, such as a PR sentinel and a twice-daily refresh, may keep one each, and its charter says so.
- Use a time wake-up (`delaySeconds` or `at`) for a cadence. Use `until.check` with a read-only script for a sentinel.
- At the end of a wake, schedule the next one and end with one line.
- A member never stops on its own. Only the lead stops it or changes its cadence.

Typical cadences, to confirm with the human: a chat watcher every 10 minutes in working hours, one evening check and none overnight, hourly at weekends, every 1 to 2 minutes in a change window. A rollout watcher every 20 to 30 minutes. A sanity checker a few times a day.

## Sentinels: wake on change

A sentinel is a read-only script that a member runs with `ScheduleWakeup` `until.check`. The member wakes when something material changed, at the deadline, or when the check can't run at all (an `error` outcome).

- It finishes in under about 40 seconds and batches or parallelizes its reads.
- It compares the live state with a snapshot file and prints the differences. It exits 0 when something material changed, 1 when nothing did, and 2 on any fetch, parse or coverage failure, so a broken read is never taken as "unchanged".
- Material means a state the lead cares about: merged, closed, ready for review, approved, changes requested, checks newly failing, or a new head commit.
- Typical settings are `everySeconds` 300 and an explicit `deadlineSeconds` such as 43200 (12 hours). An exit of 2 doesn't wake the member, so on every deadline wake, run the script once by hand. Exit 1 means nothing changed, so reschedule silently. Exit 2 means reads are failing, so record it and tell the lead if it persists.
- After waking, the member updates the snapshot only for the rows it reviewed, so later changes aren't lost.

For PRs, use `scripts/pr-sentinel.py` as is. It reads a registry of `{repo, number}` entries, fetches each PR's state, draft flag, review decision, head and check results, and compares them with the snapshot:

```bash
python3 ~/.agents/skills/orchestrator/scripts/pr-sentinel.py snapshot $FLEET/tracker/prs.json $FLEET/tracker/snapshot.json
# until.check, every 300 s:
python3 ~/.agents/skills/orchestrator/scripts/pr-sentinel.py check $FLEET/tracker/prs.json $FLEET/tracker/snapshot.json
# after reviewing what changed:
python3 ~/.agents/skills/orchestrator/scripts/pr-sentinel.py snapshot ... --only owner/repo#123
```

The same shape works for deploy checks (`pre` saves state, `post` compares) and rollout progress.

## Reporting

- Report only when something is new and material. One report per check covers everything new: for each item, who, when (in the human's time zone), a permalink, a short verbatim quote, one sentence on what it means, and whether the human must act.
- To the lead: `timeout 50 bb thread tell <lead> --message-file - <<'EOF'` ... `EOF`, so a hung call can't stall the check.
- To the human, only if the charter allows it: `bb push-notifications send --title "<80 chars max>" --body "<180 chars max>" --thread <lead>`, and confirm the output names the channels it reached. `--thread` only sets what a click opens. Test the push from the member itself during setup. A member without push permission tells the lead, and the lead forwards. Start titles with a prefix the human can scan, such as `ACTION:` when they must answer or `PROBLEM:` for harm to users.
- A member's flares appear in the lead's Flares tab. Whether they push depends on the human's notification settings, and child threads default to `input-only`, so never rely on them alone.
- Nothing new means no message, no push and no flare.

## Liveness

Permanent members fail quietly: a wake-up can fail to schedule, a plugin or provider error can break a turn, and nothing tells the lead.

- The lead keeps its own audit wake-up, every few hours while coverage matters, overnight too if the human needs overnight coverage.
- Keep permanent members on the lead's machine where possible, because the audit reads their state files. A remote permanent member includes its last successful check and next wake in every message to the lead, and sends a one-line heartbeat at least every few hours.
- Each audit compares the roster with each member's `state.json` loops (last successful check, next wake) and with `scripts/fleet-status.py`, which also shows failed members and members waiting on a question. The script reads thread metadata only, so it's advisory.
- Judge a time loop by its cadence and a sentinel by its deadline. A member whose last successful check is older than about twice that, or whose next wake has passed, needs a look. Ask it to run a check and re-arm, and to backfill from its last good cursor. Tell the human once if coverage was lost, with the window.
- `bb jumpstart list` shows failed threads, and `bb jumpstart kick <id>` retries one. Read the error first. A retried turn may resend its last request, so reconcile anything the failed turn might have changed. If the cause is a plugin or provider, tell the human the options rather than changing plugins yourself.

## Watchers that guard a change

During a change window, the watcher's brief comes from `risk.md`: client-visible signals first, saturation against limits, the old path beside the new one, a 1 to 2 minute cadence, and an immediate alert on any user report of errors or slowness, even when unsure it's related. The window's charter says whether the watcher pushes to the human directly or the lead forwards. The lead opens and closes the window by message, and the watcher records it in `state.window`.

## Keepers of a shared artifact

A tracker keeper owns a tracker for the fleet. The default form is a Markdown status file in `$FLEET/tracker/`, a board of the PRs the fleet owns, or the human's existing site, whichever the human already uses.

- It is the only member that writes the artifact. Others send it changes.
- Each data source has an owner, a freshness limit and a refresh trigger (an event such as a merge, or a time). Show each number's source and age.
- Before publishing, it backs up the current version and diffs the live copy against its source, so a concurrent writer's change isn't overwritten. It runs the artifact's tests, publishes, checks the live result, and keeps a tested way to restore the backup.
- It never overwrites the human's edits. Use a conditional or versioned write where the store supports one. Otherwise re-read and re-diff immediately before publishing. If the human changed something since the last read, the human's version wins, including deletions, and conflicts go to the lead.
- The human controls what they want to control, such as adding, editing and removing milestones. Test that their editing works. Don't lock them out to keep the data tidy.
- `comms.md` covers what to track and how to frame progress.

## Sub-leads

When a large delegated batch would flood the lead thread, give it a sub-lead.

- The sub-lead gets its own brief, runs the batch's phases, keeps `<batch>/STATUS.md`, and runs its own watcher for the batch's conversations.
- It escalates only questions aimed at the human, confusion about what was asked, a delegation in trouble (refused, disputed, unowned or about to break something), and risk to a deadline. Routine replies stay with it.
- It archives each of its helpers as soon as it has read the helper's result, not at the end of the phase. Its reports to the lead list any helpers still running and why.
- Keep it light-touch. Once work is with its owners, the sub-lead watches and notes state. It doesn't chase reviews, follow merges or write digests nobody asked for.
