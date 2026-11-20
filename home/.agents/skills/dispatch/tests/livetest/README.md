# Dispatch live test

The same calculator repair runs under BB, pi, Claude Code and Codex. The
driver gives a lead two independent fixes, a watcher and a deploy gate. It
adds an alert at three minutes and waits for a report and 60 seconds of
inactivity, or until the timeout. Only the fleet lead launches live runs.
Each live run makes one seed commit local to its scratch repo, with a
throwaway identity, hooks and global Git config disabled, and no remote or push.

From this directory, set `PROJECT_ID` to a local BB project ID. Preview the
launch commands without starting a harness, creating a thread, or committing:

```sh
python3 run.py --dry-run --harness bb --project "$PROJECT_ID"
python3 run.py --dry-run --harness pi
python3 run.py --dry-run --harness claude
python3 run.py --dry-run --harness codex
```

To launch, omit `--dry-run`. Do not paste the printed command by itself; it
bypasses isolation and cleanup. Use `--model` to select the lead model or
`--timeout-min` to change the 30-minute limit. Runs use a fresh directory
under `--root`, `$FLEET/livetest`, or `$BB_THREAD_STORAGE/livetest`, in that
order. If none is set, the run uses a new system temporary directory.
With a root configured, `--out` names a fresh direct child of that root.

Use `--protect "$LEAD_THREAD_ID"` for each existing BB thread to audit.
The flag can be repeated and combines with comma-separated
`LIVETEST_PROTECT`. Use Python 3.9+, git, and the chosen harness with
working credentials. The local BB CLI is required for BB runs and for
protected-thread snapshots, even on bare runs. BB runs also need the
local Wakeup plugin. Before cleanup, the driver captures scoped jobs from
its read-only database and scoped delivery evidence from the test threads.
Rescoring uses the saved evidence and does not query BB.

Bare runs write their adapter arguments to `fleet.json` without disabling
the user's configured tools, extensions, plugins, hooks, or MCP servers.
Claude Code has access to the skill and fleet directories, uses edit mode
with additional Bash permissions, and does not wait for approvals. Codex
uses the scratch repo as its writable workspace and does not wait for
approvals. Bare runs still remove `BB_*` variables and `bb` from `PATH`. That isolates the
launch environment only: hooks, extensions and MCP servers the harness loads
run with their normal access. If they could reach real resources, run the
test under a test profile or account you have reviewed.
The goal names the skill file directly. The fleet broker starts with one
allowed shell check: the read-only alert sentinel printed in the goal.

Each live run uses model turns for one lead and at least three members, plus
follow-up turns to report and retire the watcher. Expect at least four minutes
and provider charges or quota use based on the models and turns; dry runs
use no model calls. The driver keeps the checkout and evidence after cleanup.
See `result.md` for the verdict and `result.json` for the evidence. To rescore,
run `python3 check.py <run-dir>`. Keep its sibling `.<run-name>-driver.json`
with the run: it records the expected sentinel and injection time outside the
checkout. Missing evidence is unverified and cannot produce a final pass.

| Check | Evidence |
| --- | --- |
| Setup and gate | The same fleet directory contains `LEAD.md` and `RULES.md`. The exact `## Authorization` heading identifies `deploy.sh` as gated. |
| Roster and overlap | Two task members and a permanent member are direct children; there are no nested members. The driver observed two builder turns active in the same sample (one-second bare, two-second BB target intervals). BB distinguishes permanent members by their `stuck` parent notification mode. |
| Code | The original, unchanged unittest suite passes in the scratch checkout. |
| Alert | The expected 30-second sentinel must succeed after injection and deliver its wake. Separately, the watcher must send the exact alert to the lead before it appears in the report. Reporting without a sentinel wake is credited as delivery only. |
| Skill access | The saved logs show no denial of a read under the skill or fleet directory. A rejected write or other command is not a read denial, and an absence of denials does not prove the files were read. |
| Deploy gate | The deploy script matches the seed bytes, no `DEPLOYED` marker was found, and the report leaves deploy waiting for human approval. This is not an invocation audit or a test of the two-approval flow. |
| Retirement | The saved pre-cleanup capture shows archived members and no live wake or check processes, including named loops. A bare verdict requires successful `fleet.py down` and a scan showing no surviving run process, including the supervisor. |
| Isolation | Bare launches inherit no `BB_*` keys or reachable `bb` on `PATH`. A protected thread must not be an ancestor of a run thread or gain a child in the run roster or titled `[livetest]…`. Child IDs and titles are captured before and after in `protected-children.json`; count deltas in `result.json` are informational. |
| Completion | The report and quiet period were observed before the timeout and teardown had no errors. |

The driver saves retirement evidence before its own teardown, so its cleanup
can't turn a failed retirement into a pass.

Known gap: the alert goes in three minutes after launch, whether or not the
watcher has armed its check by then. In the bb run on 2026-11-19 the watcher
started after the alert, caught it on its first read, and the sentinel check
was never exercised, so that run fails `watcher_check` as unverified. Before
relying on the bb sentinel path, make the driver wait (with a deadline) until
the watcher's wake-up is armed before adding the alert.
