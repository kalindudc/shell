# Where these rules come from

This skill distills one lead thread that ran an infrastructure migration for three days: a proxy replacement, an internal app's DNS cutover, and dozens of cleanup changes handed to other teams. In those three days it handled about 200 messages from the human and more than 1,000 reports from about 100 child threads. Each lesson below names the rule that answers it, so you can judge when a rule matters and when it can bend.

## What went wrong

| What happened | Rule that answers it |
|---|---|
| The human missed expected updates, including an announcement they were waiting for. The watcher reported only through child flares, which weren't a proven route to the human's devices. Nothing had ever sent a push, and the watcher's notification mode was set without telling the human. | Reporting routes: three routes, each tested; tell the human each member's mode. |
| The lead's anchor went unwritten for two days across seven compactions, and a keeper's charter grew to 18 KB of dated notes. | Keep one truth; re-read `LEAD.md` after compaction; prune charters. |
| Readiness briefs were copied from an old runbook. None asked about load, and the watcher's metric couldn't see the new layer's own errors. It reported "clean" during ten minutes of errors. | Ask what's different about the new path; monitoring that's proven to work; empty data is unknown. |
| During the incident the lead chose certainty over mitigation, with a tested revert ready, which added about 8 minutes of impact. | Mitigate first. |
| The first cut had no armed watchdog. The only proposal before the cut still needed the human to decide and confirm the revert, and detection and diagnosis took most of the 18 minutes. | Advance-approved automatic rollback, narrow and deterministic. |
| Members edited PRs already handed to owning teams, put dates in owner messages, and filled boards with other teams' PRs. | Delegated work is hands-off; track only what we own. |
| Extra configuration changes the human hadn't asked for, per-cluster lists where a cluster-set precedent existed, two PRs that could have been one, and PRs offered for review with failing CI. | Keep changes small; follow precedent; failing CI is never "ready". |
| A brief said "rework completely", and the site the human relied on was rebuilt as a docs site, losing its cards, timelines and diagrams. | Briefs for something the human uses list what to keep, show before and after, and stay local until approved. |
| Design-heavy site work went to a cheaper implementation model, and the human asked for a stronger one. | Design and usability work goes to design roles. |
| Paste-ready messages lost newlines and links, missed the human's opener and closer, went to the wrong channel, and swung from too long to too short. | Templates and a linter after the second correction; render before saving; the owner's designated channel. |
| Progress shown as "33 of 199" read like nothing had happened. | Frame progress as built, moved and left, computed from data. |
| The fleet sprawled: the human said the work had "gotten a bit out of hand", and one sub-lead had 24 helpers. | About 8 live members; whoever spawns a thread archives it; a fleet sweep each phase. |
| The human had to ask for child-thread cleanup five times in three days, because archiving was a batch chore done on request. | Archive in the same turn a result is read, as a step of every lead wake. |
| A watcher's wake-up failed to schedule and it missed three hours. A plugin's tool schema made a keeper's turns fail on one model family. | Liveness audits on the lead's own schedule; per-loop health in the state file. |
| The lead nearly re-delegated work other members already had, and owners were nearly asked twice. | Check the roster first; reconcile everything for a team before contacting it. |
| The human replaced a member and the old one kept running until the human noticed. | Stop, confirm and reconcile before steering. |
| A deploy was started before two PRs had merged, so it shipped without them. | Pin and verify the revision per target. |
| Members briefed under one name showed up under bb's generated name. | One name per member: the one bb gives its thread. |

## From the skill's first runs

The skill was then used for four hours in the same lead thread, adopted mid-run, and for a new fleet that fixed a plugin on a memory-constrained laptop.

| What happened | Rule that answers it |
|---|---|
| The adopting lead read only the entrypoint and one reference, so it never saw the progress and reporting guidance. | Read every reference once at setup or adoption; the most-corrected rules live in `SKILL.md`. |
| Progress numbers drew eight corrections in three hours. Counting only finished work read as "barely 1%", and counting finished plus in flight read as a misleading 93%. Two totals side by side confused everyone. | The five progress-number rules: fixed baseline, percentage for finished work only, in-flight beside it, one headline, a label on every number. |
| 61 of the lead's 90 replies in four hours answered member reports, and about a third of those were progress ticks or repeats of a report already passed on. Members sent a mid-job message and then the same content as their final answer. | No progress ticks; one line at most when a report changes nothing; task members report once, in the final answer. |
| Old persona names survived adoption, and the human found two names per member confusing. | One name per member everywhere; switch old names on adoption. |
| The watcher relayed an owning team's own certificate problem, and the lead researched and drafted a fix. The human said not to micromanage delegated threads. | An owner's problem with their own change is theirs; a narrow filter for watchers of delegated work. |
| A member's final report arrived after the lead had archived it on its early message. | Archive after the final answer arrives. |
| On a laptop that had already crashed from memory pressure, the lead handed out one test slot at a time, and builders worked in worktrees with one integrator. It worked well. | Scarce-resource slots and the integrator role. |
| The human asked for a listing name with a likely typo, and the lead applied it exactly without saying so. | Do it as asked, and point out the likely typo in one line. |
| A short fleet skipped permanent members, the push test and paging, and reported in the thread. That was right for a few hours with the human present. | Scale setup to the fleet's life. |
| Large delegated batches each had a sub-lead, informally, and one grew 24 helpers. | Child leads with a charter, a member budget and a two-level limit. |

## From making the skill run on any harness

| What happened | Rule that answers it |
|---|---|
| Every spawn, message, wake-up and push step was a bb command, so colleagues on bare pi, Claude Code or Codex couldn't run the process. | The skill names primitives. bb keeps its own, and bare harnesses use `scripts/fleet.py` (Running on any harness). |
| The change needed live tests of the whole process, and the human said: "Make sure the live test is isolated and not on my existing thread." A test inside a real fleet would mix test members, messages and archives with real work. | Test the process itself in isolation: a scratch directory, threads or processes made for the test, cleanup afterwards, and never the human's existing threads or fleets. |
| The live test's prompt told the lead to use only built-in tools and keep worktrees in the scratch directory, so the bb lead avoided the `spawn` tool and bb-managed worktrees. The human: "The skill shouldn't limit any other user configured tools ... Any available tools are ok." | The primitives are a minimum, not a list of allowed tools. Members keep the human's harness configuration, and flags only grant access or suit headless runs. Isolation decides where a test runs, not which tools it uses. |
| In the live tests, both Claude Code leads never read the skill: its directory and the fleet's were outside their working directory, and with permission prompts off every read was denied. Builders in worktrees couldn't read their briefs either. | Give each harness access to the skill and fleet directories in `fleet.json` before `init` (`harnesses.md`). |
| A review found that on a bare harness a relayed approval proves nothing, because anyone on the machine can write an inbox message under any name, and that pausing a child lead left its workers waking. | Both yeses and the run happen in one human session, with no relay by `tell`; `fleet.py pause --tree` after the child lead confirms. |
| A colleague planning an overnight fleet on bare Codex would have picked an interactive lead that does nothing while they sleep, and couldn't tell where worktrees, flags and wake checks had to be set. A stopped broker left checks looking alive with nobody to deliver their wake-ups. | Two explicit bare entry paths, a headless lead for unattended fleets, `fleet.json` before `init`, and a dead broker counted as a blocker. |

## From the first unattended merge

| What happened | Rule that answers it |
|---|---|
| The human asked the lead to "run all CI and if it's self approve then approve and merge otherwise I will figure it out in the morning", then went to sleep. The lead read that as "stop on any obstacle", and wrote "stop on any finding, don't fix" into the merge brief and into its own wake-up prompt. The automated reviewer requested changes 13 minutes after the merge request, with two real, fixable bugs, and nothing was fixed for 8 hours. The human: "Why did you not just get this done, fix it, clear [the reviewer] and merge the PR". | Carrying work to done: a condition reserves only what it names, findings on our own change are ours to fix, no stop in a brief or wake-up prompt the human didn't ask for, and foreseeable forks are asked about before the human leaves. |
| The lead's overnight wake-up fired only on "merged" or a change of mergeable state. The reviewer blocked the PR 44 seconds after it was armed, the PR stayed blocked, and 35 checks passed over it until the 3-hour deadline. The member that had been watching retired at "waiting on the reviewer". | A watch fires on whatever blocks its goal; report at an end state; at a deadline, act and re-arm. |
| Both bugs got past the lead's own reviews. The last round of fixes had no critic pass, and the lead knew it. | Run the reviewers you can run before an unattended merge. |
| The replacement PR drew a third finding of the same kind: a first turn stopped or killed before the harness reported its session lost the member's brief. The morning fix had covered only a launch that never started. | Fix the class, not the instance: when a reviewer finds one input-loss path, test every path that can interrupt the same step. |
| In the morning the lead said the PR's branch couldn't be updated because the machine that pushed it was gone, and opened a replacement PR. The branch was still on the forge, and nobody checked. The replacement's approval card then expired unanswered. The human: "Why did you make a new PR??" | Prove a blocker with a read; update what exists rather than replace it. |

## What worked, and is kept

- A rules file every member reads first, an anchor file for the lead, and briefs as files with a short task message per slice.
- Evidence with every claim, and "old notes are leads, never facts".
- An independent verifier on a different model, and three critics on three model families for risky changes, consolidated into one table.
- A phase pipeline for large batches, ending in one review document for the human.
- Watchers built to survive compaction: charter re-read every wake, cursors in a state file, one pending wake-up, short wake prompts pointing at a check file, and an "already told" list.
- Cheap sentinel scripts on `until.check`, so keepers wake on change or at a deadline, not on every poll.
- Two-step approvals in the question panel, with exact commands and undo.
- Binary change risk decided by the reviewer, with a short list of evidence for high-risk changes, and one high-risk exposure at a time.
- Short morning packets and ship lists in merge order, with the check to run after each deploy.
- Honest pushback when a goal couldn't be met safely.
- Cleanup rounds with a table of who stays and why.
- Unrelated urgent work isolated in its own thread, and heavy repository work moved to remote machines.
- Continuous archiving after the skill was adopted: every task member was archived within minutes of its result, and the human didn't have to ask for cleanup again.
- A stall check on a watcher's state file between liveness audits, which the adopting lead added on its own.
