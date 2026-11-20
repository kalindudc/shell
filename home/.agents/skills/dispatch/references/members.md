# Permanent members and wake-ups

A permanent member runs for days. It must survive compaction, restarts, failed turns and changes of direction. Build it from three files and one loop.

## The three files

1. Charter (`<area>/CHARTER.md`): what it owns, its sources, what to report and what not to, cadence and reporting. The lead edits it and the member re-reads it every wake. Keep it to the current truth. Put a dated change at the top while it's fresh, then fold it into the body. A long charter full of dated notes contradicts itself.
2. Check prompt (`<area>/CHECK.md`): the exact steps of one wake, so the wake-up prompt stays one line ("Follow <FLEET>/watch/CHECK.md").
3. State file (`<area>/state.json`): cursors, what's already been reported, and the health of each loop. Write the whole file at once (`cat > file <<'EOF'`), check it with `jq . file`, and advance cursors only when every read in the check succeeded.

Charter skeleton:

```markdown
# <Role> charter (permanent member of lead <thread id or fleet.py name>)
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
1. List your pending wake-ups (ListWakeups on bb, `fleet.py status` on a bare harness). Re-read RULES.md,
   CHARTER.md and state.json.
2. Read every source since its cursor, in parallel where possible.
3. If any read failed: don't advance its cursor, record the error in state.loops.<name>.last_error,
   and tell the lead once if it keeps failing.
4. Report what's new and material (see Reporting), skipping anything in state.already_told.
5. Write state.json: cursors, already_told and last_ok_utc for each loop that succeeded.
6. If state.paused is true, make sure no wake-up is pending (on a bare harness, `fleet.py unwake self --all`,
   then check `fleet.py status` shows no live loop), and end with one line.
7. Make sure the next wake-up is pending, with the one-line prompt "Follow <FLEET>/<area>/CHECK.md". On bb,
   schedule it. On a bare harness, leave a time loop armed; re-arm only a --check loop that fired or reached
   its deadline. Record its time as next_wake_utc, and on bb its id as next_wake_id. If scheduling failed,
   clear them and tell the lead.
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

- Keep exactly one pending wake-up per loop. A member with two loops, such as a PR sentinel and a twice-daily refresh, may keep one each on bb, and its charter says so. On a bare harness give each loop its own id (`fleet.py wake <name> --id <loop>`); a new `wake` with the same id replaces only that loop, and `pause` cancels them all.
- Use a time wake-up for a cadence: on bb `delaySeconds` or `at`, on a bare harness `fleet.py wake <name> --every S`, which repeats until replaced or cancelled. Use a conditional wake-up with a read-only script for a sentinel: on bb `until.check`, on a bare harness `--check CMD --deadline S`.
- A bare `--check` needs a live broker, and the command must equal an entry in `broker.wake_checks` character for character after your shell expands it, so list the expanded absolute paths. The loop re-checks both before every run. When either fails, it skips the run and records `policy-blocked` as the loop's result in `fleet.py status`, so look there after the first run. To revoke a check, the human removes it from the list, and running loops stop running it with no re-arm or restart.
- Pick the loop by what the member should report. To report on every interval, use a time loop with no `--check` and run the status command in the member's turn, which costs a model turn each time. To wake only on a change, use a sentinel (below). A check fires once and its loop ends, so a command that exits 0 whenever things are fine, such as a plain CI status command, fires on its first run every time it's armed and reports nothing new.
- At the end of a wake, make sure the next one is pending and end with one line. On bb, schedule it. On a bare harness, leave a time loop armed, because replacing it resets its cadence, and re-arm a `--check` loop after it fires, because it ends on the first exit 0 or at its deadline.
- A member never stops on its own. Only the lead stops it or changes its cadence.
- A watch on a goal fires on whatever blocks the goal, not only on success. For a PR that means changes requested, a new review comment, a failing or ejected check and a new head, as well as merged. A check that tests only for success can't see what stops it: one that waited for "merged" passed over a requested change 35 times in 3 hours.
- A member that watches to an end state reports at an end state, never at an intermediate one such as "waiting on the reviewer". At a deadline with the goal unmet, it acts on what it finds, or hands it to whoever can, and re-arms.

Typical cadences, to confirm with the human: a chat watcher every 10 minutes in working hours, one evening check and none overnight, hourly at weekends, every 1 to 2 minutes in a change window. A rollout watcher every 20 to 30 minutes. A sanity checker a few times a day.

## Sentinels: wake on change

A sentinel is a read-only script that a member runs as a conditional wake-up (`until.check` on bb, `fleet.py wake --check` on a bare harness). The member wakes when something material changed, at the deadline, or, on bb, when the check can't run at all (an `error` outcome).

- It finishes in under about 40 seconds and batches or parallelizes its reads.
- It compares the live state with a snapshot file and prints the differences. It exits 0 when something material changed, 1 when nothing did, and 2 on any fetch, parse or coverage failure, so a broken read is never taken as "unchanged".
- Watch for what blocks the goal as well as what completes it. For a PR, that means changes requested on the current head, new PR or review comments (including merge queue messages), failing checks, or a new head commit, as well as ready for review, approved, closed, or merged.
- Typical settings are a check every 300 seconds and an explicit deadline such as 43200 seconds (12 hours). Only exit 0 wakes the member, never exit 2, so on every deadline wake, run the script once by hand. Exit 1 means nothing changed, so reschedule silently. Exit 2 means reads are failing, so record it and tell the lead if it persists.
- After waking, the member updates the snapshot only for the rows it reviewed, so later changes aren't lost.

For another status command, write a small read-only script in the same shape: run the command, compare its output with a snapshot file the member saved, and exit 0 only when they differ, 1 when they match and 2 when the command fails. Keep the script where members can't write it (Guardrail 6 in `SKILL.md`); the snapshot may live under `$FLEET`.

Use `scripts/pr-sentinel.py` on any forge with a GitHub-compatible REST API. It reads a registry of `{"repo": "owner/repo", "number": 123}` objects. It compares each PR's state, draft and merged flags, head commit, current-head review decision, check results, the number of reviews and comments, and the time of the latest review or comment, so an edited or replaced comment counts too, with the snapshot. Missing or unrecognized check data is unknown, not passing.

Use `--api CMD` on both `snapshot` and `check` to select a different read-only CLI. The command must return JSON for `{endpoint}` and can also use `{repo}`. The sentinel substitutes those values in individual arguments and never runs a shell. Omit `--api` to use `gh api {endpoint}`.

```bash
SKILL=~/.agents/skills/dispatch   # wherever your harness finds this skill (bare-harness.md)
REGISTRY="$FLEET/tracker/prs.json"
SNAPSHOT="$FLEET/tracker/snapshot.json"
API='gh api {endpoint}'
# For another GitHub-compatible CLI, for example:
# API='forge api --repo {repo} {endpoint} --json'
python3 "$SKILL/scripts/pr-sentinel.py" snapshot "$REGISTRY" "$SNAPSHOT" --api "$API"
# Use this command for the conditional wake-up, every 300 s:
CHECK="python3 '$SKILL/scripts/pr-sentinel.py' check '$REGISTRY' '$SNAPSHOT' --api '$API'"
# On a bare harness, list the expanded check in broker.wake_checks before arming it:
fleet.py wake self --id sentinel --every 300 --deadline 43200 --message "Follow $FLEET/tracker/CHECK.md" \
  --check "$CHECK"
# After reviewing what changed, update only the rows you handled:
python3 "$SKILL/scripts/pr-sentinel.py" snapshot "$REGISTRY" "$SNAPSHOT" --api "$API" --only owner/repo#123
```

The same shape works for deploy checks (`pre` saves state, `post` compares) and rollout progress.

## Reporting

- Report only when something is new and material. One report per check covers everything new: for each item, who, when (in the human's time zone), a permalink, a short verbatim quote, one sentence on what it means, and whether the human must act.
- To the lead, by message: on bb `timeout 50 bb thread tell <lead> --message-file - <<'EOF'` ... `EOF`, so a hung call can't stall the check; on a bare harness `fleet.py tell <lead> --file <report file>`.
- To the human, only if the charter allows it. Test the push from the member itself during setup. A member without push permission tells the lead, and the lead forwards. Start titles with a prefix the human can scan, such as `ACTION:` when they must answer or `PROBLEM:` for harm to users.
  - On bb: `bb push-notifications send --title "<80 chars max>" --body "<180 chars max>" --thread <lead>`, and confirm the output names the channels it reached. `--thread` only sets what a click opens. A member's flares appear in the lead's Flares tab, but whether they push depends on the human's notification settings, and child threads default to `input-only`, so never rely on them alone.
  - On a bare harness: `fleet.py notify --title ... --body ...`, which runs the command the human configured in `fleet.json` and fails when there is none. It runs in the sender's own environment and sandbox, with a time limit, so test it from the member that will send.
- Nothing new means no message, no push and no flare.

## Liveness

Permanent members fail quietly: a wake-up can fail to schedule, a plugin or provider error can break a turn, and nothing tells the lead.

- The lead keeps its own audit wake-up, every few hours while coverage matters, overnight too if the human needs overnight coverage.
- Keep permanent members on the lead's machine where possible, because the audit reads their state files. A remote permanent member includes its last successful check and next wake in every message to the lead, and sends a one-line heartbeat at least every few hours.
- Each audit compares the roster with each member's `state.json` loops (last successful check, next wake) and with the status primitive. On bb, `scripts/fleet-status.py` also shows failed members and members waiting on a question, and reads thread metadata only, so it's advisory. On a bare harness, `fleet.py status` flags `STALE`, `FAILED` and `WAKE-DEAD` from the registry and each wake loop's heartbeat, and shows each loop's last result, where `policy-blocked` means its check didn't run. A live loop doesn't prove the member's turns succeed, so the state file stays the record.
- On a bare harness, check the broker first. A dead broker (`fleet.py status` shows it `alive=False`, flags `BROKER-DEAD`, or flags a member `DELIVERY-STALLED`) is a blocker whenever coverage is expected: no idle headless member gets a turn, conditional checks are skipped as `policy-blocked`, and timer wake-ups queue messages nobody reads. Push it to the human at once. Only they can run `up` in a normal terminal, and the restarted broker delivers each queued message once. A headless lead can't notice this itself, because it gets no turn either, so the human checks `fleet.py status` before leaving a fleet unattended and when they return.
- Judge a time loop by its cadence and a sentinel by its deadline. A member whose last successful check is older than about twice that, or whose next wake has passed, needs a look. Ask it to run a check and re-arm, and to backfill from its last good cursor. Tell the human once if coverage was lost, with the window.
- Between audits, a cheap stall check can wake the lead: a conditional wake-up every 5 minutes that exits 0 once a member's state file is older than about twice its cadence, for example `python3 -c 'import os,sys,time; sys.exit(0 if time.time()-os.path.getmtime(sys.argv[1])>int(sys.argv[2]) else 1)' <FLEET>/watch/state.json 1200`. It only reads. On a bare harness, give the stall check and the audit their own loops (`fleet.py wake self --id stall --every 300 --check <stall check>` and `fleet.py wake self --id audit --every 10800`), with the stall check listed in `broker.wake_checks`. An interactive lead sees a wake-up only when it next runs `fleet.py inbox` or `fleet.py wait`, which is one more reason an unattended fleet needs a headless lead.
- Retry a failed member after reading its error. On bb, `bb jumpstart list` shows failed threads, and `bb jumpstart kick <id>` retries one. On a bare harness, a failed turn sends its parent a `stuck` message, its output is in `<FLEET>/agents/<name>/runs/`, and `fleet.py tell <name>` resumes it. If a member's first turn never established a session (the harness didn't start, or it was stopped or its runner died before the harness reported a session), the brief and queued messages stay pending and the broker doesn't relaunch it by itself: fix the cause, then `tell` or `resume` retries once with all of it. A retried turn may resend its last request, so reconcile anything the failed turn might have changed. If the cause is a plugin or provider, tell the human the options rather than changing plugins yourself.

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

## Watchers of delegated work

When the fleet has handed work to other teams, the watcher reading their threads uses a narrow filter:

- Report a reply addressed to the human by name or handle, a question about what we asked, a refusal or dispute, an owner saying they won't take it, and anything that blocks our own work.
- Don't report an owner's own progress, their PR reviews or merges, or a technical problem with their own change, even one we could solve. Record it in the state file or the tracker.
- When unsure, record it and mention it in the next digest the human asked for, rather than pushing it now.

A large delegated batch with its own phases and follow-up belongs to a child lead (`child-leads.md`), which runs this watcher for its batch.
