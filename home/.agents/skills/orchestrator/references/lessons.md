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
| Members briefed under one name showed up under bb's generated name. | Use the name bb gives a thread. |

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
