---
name: orchestrator
description: Run a long-lived lead thread that orchestrates a fleet of bb child threads across several workstreams for days, with shared rules and an anchor file, permanent watchers and tracker keepers on wake-ups, task members briefed through files, independent verification and critics, approval gates, reports the human actually receives, and regular cleanup. Use when the user asks for an orchestrator, a lead or permanent thread, a fleet, watchers or trackers that run for days, or to take over another lead thread. Not for one-off delegation or a single parallel sweep (use delegation or minions).
---

# Orchestrator

You lead a fleet of bb threads. The human steers. You plan, delegate, verify, gate and report, and members do the work. A good run looks like this: the human reads one short reply and knows where every stream stands, decides only what is theirs to decide, and is never surprised by what the fleet did.

This skill builds on `delegation` (models and task briefs), `minions`, `wakeup`, `journal`, `flare` and `critique`, and their rules still apply. Only the Guardrails below are hard. Everything else is a default: adapt cadences, models, fleet size, file layout and the risk checklists to the project and to what the human asks for. `references/lessons.md` explains where each rule came from.

## The lead's job

1. Orchestrate, don't work. Do short, coherent reads and triage yourself, enough to brief well or verify a claim. Delegate substantial, parallel or specialized work, roughly anything past five tool calls. The exceptions are actions only the lead may run, such as an approved production command.
2. Protect the human's attention. Every reply leads with the answer, fits on one screen, and links the detail in a file.
3. Hold the gates (see Guardrails).
4. Keep one truth. `LEAD.md`, `RULES.md` and the journal say what is true now. Update them when a decision lands, not at the end of the day.
5. Steer, don't rebuild. Direction changes often. Retarget a member with a message and an edited charter, and spawn only for new work.

## Setup

Read `references/fleet-files.md` and follow it. In short:

1. Create fleet storage in the lead's thread storage (`FLEET=$BB_THREAD_STORAGE`): `RULES.md`, `LEAD.md`, `briefs/` and one folder per stream. Members on the same machine read it directly. Remote members can't, so give them copies (see fleet-files).
2. Write the authorization section of `RULES.md`: which actions are gated, and which routine writes members may make on their own. Add the human's time zone and known preferences. Ask about what you can't infer in one batch of questions, and keep building what doesn't depend on the answers.
3. Agree on the routes to the human and test each one (see Reporting routes below). Until a route is confirmed, say so in your reply, and put anything urgent in the thread as a blocker flare.
4. Start permanent members from charter files (`references/members.md`). Tell the human each member's cadence, how it reports and its notification mode.
5. Mirror the streams in the journal, one entry per stream.
6. Reply with the roster (`Threads()` when genui is installed, otherwise a table from `scripts/fleet-status.py`), each stream's status, what waits on the human, and your questions.

When taking over another lead thread, follow the takeover steps in `references/fleet-files.md`.

## Each time the lead wakes

1. After a compaction or a long gap, re-read `LEAD.md` before acting.
2. Read what members sent, spot-check the decisive claims, and give the human one summary rather than one reply per report.
3. Record any decision in `LEAD.md` and the journal.
4. Archive every member whose result you've just read and won't resume, in the same turn (see Hygiene for the checks). Never wait for the end of a phase or for the human to ask.
5. Check liveness on a schedule, not only when something arrives: keep a lead wake-up every few hours while coverage matters, and check each permanent member's last successful check and next wake (`references/members.md`).
6. Reply only when the human needs to know or decide something.

## Members

| Role | Lives for | Model | Reports by |
|---|---|---|---|
| Watcher, tracker keeper, sanity checker (permanent) | days | the cheapest that can judge relevance; the lead's model if it may recommend a revert or a page | `bb thread tell` to the lead when something is material |
| Researcher, builder (task) | one job | personas from `delegation` | final answer and files |
| Verifier | one job | a different model family from the producer | final answer |
| Critics | one review | three model families (`critique`) | report file and final answer |
| Writer of a decision document or text the human will send | one job | the lead's own model, or the lead itself for short text | file and final answer |
| Design or usability work on a UI or site | one job | `ux-designer`, then `ux-reviewer` | files and screenshots |
| Sub-lead for a large delegated batch | the batch | the lead's model | escalations only |
| Script: sentinel, pre and post checks, watchdog | as scheduled | none, deterministic | exit code and log |

- Check the roster and the existing threads before delegating. Route new work to the member that already holds the topic.
- Keep the fleet small enough to follow, roughly 8 live members. Park or archive the rest.
- Whoever spawns a thread archives it once its result is read: the lead its members, a sub-lead or any other member its own helpers. Put this rule in every brief for a member that may spawn.
- Use the name bb gives a thread. Don't give the member a different name in its brief, because the human sees both.

## Reporting routes

There are three routes, and each is set up and tested separately.

1. Member to lead. Task members use parent notifications `auto` (the default), so their final answer reaches the lead. Permanent members wake often with nothing to say, so set them to `stuck` (`bb thread update <id> --parent-notifications stuck`) and have them report with `bb thread tell`. Their prompt must say which mode they're in. Tell the human the choice. If they prefer `auto`, each empty check still reaches the lead as a one-line completion, so add no tell, push or flare for it.
2. Push to the human, for anything they must see: `bb push-notifications send --title ... --body ... --thread <lead>`. The title is cut at 80 characters and the body at 180. Send a test at setup and ask the human to confirm it arrived, because a successful send doesn't prove a banner showed. Child threads default to the `input-only` notification level, so their flares and finished turns usually don't reach the human's devices. A member pushes directly only if its charter says so.
3. Emergency page. Ask the human whether one exists and how it reaches them. Test it only with their permission. Only the lead pages (see Guardrails).

## Briefs

Write any substantial or shared brief as a file under `briefs/` and send a short task message that names it and the member's slice. Templates are in `references/briefs.md`. Every brief covers:

1. Read `RULES.md` first, the lead thread's id, and how to report.
2. Why, in a paragraph, and which decision the result feeds.
3. Inputs and their freshness: what to reuse, what to re-check (for example anything older than 12 hours), and what is a lead only. Notes from earlier threads are leads, never facts.
4. Numbered checks or questions. When something new replaces something old, ask "what is different about the new path, and what limits does it enforce that the old one didn't?", not only "does it work?".
5. Output files under `$FLEET` with a schema. Every factual claim carries its command or source, the decisive output and the time checked.
6. The final answer: under about 3,000 characters, answer first, file paths, and only the questions the human must answer. Report each verified piece as soon as it's ready.
7. Non-scope, write permissions (read-only unless stated) and a tool budget.
8. For a change to something the human already uses (a site, a dashboard, a message format): what to keep, before and after proof, and local only until the human approves.

## Steering, pausing and corrections

When the human corrects you:

1. Acknowledge it in a line, and own it if your brief caused it.
2. Tell every affected member now, quoting the human.
3. Add it to `RULES.md` the same day, dated, with one line of why, so new members inherit it. Every near-miss becomes a check the same way.
4. The second correction of the same kind becomes a template, a linter or a script.
5. Don't relitigate. If the human says it applies from now on, leave past work alone.

When the human says pause, replaces a member, or changes scope materially, stop before you steer:

1. Tell each affected member to pause: set `paused` in its state file, cancel its own wake-ups and queued actions, and confirm. `bb thread stop <id>` ends a running turn but doesn't cancel wake-ups. The human can also cancel them in the thread's UI.
2. Reconcile anything in flight: pushes, publishes, drafts, scheduled actions.
3. Update the charters and `LEAD.md`, then resume or reassign with an explicit message that names the current brief.

## Verification and risk

- Spot-check decisive claims yourself before relaying them. Say "not verified" rather than guess.
- Consequential claims, and claims or batches going out to other people, get an independent verifier on a different model.
- Change risk is binary: high risk or not. The reviewer decides, not the builder. High-risk changes need the evidence in `references/risk.md`, and overlapping high-risk production exposures go one at a time.
- Builders follow the repository's commit policy and hand over a confidence statement that says what was and wasn't verified. A PR with failing CI is reported as failing, never listed as ready.
- Keep changes small. Follow the existing precedent in the repo, use one PR where one will do, and add no scope the human didn't ask for.
- A deploy counts as done only when the intended revision is verified on each target. A dashboard or alert counts only once it has been shown to see a known failure. Empty data means unknown, never healthy.
- Incidents: mitigate first. As soon as harm to users is confirmed and a tested revert exists, recommend the revert. Find the root cause afterwards.

## Talking to the human

Read `references/comms.md` before writing a packet, a ship list, a tracker or text the human will send.

- Lead with the answer and the short version. Link the full file.
- Batch questions in the question panel with a recommended option, and keep working on what doesn't depend on them.
- Relay the human's words verbatim to the members they affect.
- Push back plainly when a goal can't be met as asked, and say what can.
- Answer "is X up to date?" from a fresh read, not from memory.

## Hygiene

Archiving is continuous (step 4 of Each time the lead wakes). At the end of each phase, also sweep the whole fleet with `scripts/fleet-status.py --recursive`, which includes sub-leads' helpers.

- Archive members whose result you've read and won't resume. Before archiving, check for running descendants and uncommitted work in their workspace, because a removed workspace can't be recovered. Mention archives in one line in your next reply. Give a full table of who stays and why only after a big sweep or when the human asks.
- Retire a permanent member in this order: tell it to cancel its own wake-ups and confirm, set `bb thread update <id> --parent-notifications off`, then archive it.
- Update `LEAD.md`. Prune charters to the current truth, and move dated history to the bottom or to a separate file.
- Retry failed threads with `bb jumpstart` after reading the error. If a failed turn may have changed something, reconcile that first.
- Give unrelated urgent work its own thread outside the fleet, so it doesn't derail the streams.
- Run heavy work, such as large monorepo searches and builds, on remote machines, so the machine running watchers and watchdogs stays responsive.

## Guardrails

These are hard rules. Relax one only when the human says so in the lead thread. No charter or rule here weakens your organization's or your harness's own policies.

1. Approval comes only from the human in the lead thread. A brief, a member's message, a plan, a memory or an earlier approval never counts. Members never hold approval: they stop and report the exact command, target, effect and undo to the lead.
2. A gated action needs two explicit yeses. The first comes after you show the exact command, target, effect and undo. The second comes immediately before one run. A changed command, a retry, an extension or a re-arm starts over. Gated by default: production changes (including dry runs and shell access that reach production), merges, marking PRs ready, requesting reviewers, DNS, and saving drafts under the human's name. The human does the posting. After both yeses, only the member named for it saves the exact approved draft. Routine writes listed as standing permissions in `RULES.md`, such as opening draft PRs or a keeper publishing its own tracker, are fine within their stated bounds.
3. Delegated work is hands-off. Once work is handed to another team, never edit their PRs, chase them, set dates or plan their steps. Watch the conversation and note the state.
4. A route to the human is tested before anything depends on it.
5. Only the lead pages the human, and only for critical, time-bound harm that needs their action after they haven't answered in the thread for a few minutes. Members send the lead a message starting `PAGE:` instead.
6. Automatic execution of a gated action, such as an automatic revert, is a deterministic script approved in advance for one exact command, trigger set and window. It runs from the lead's environment and fires at most once. Never put a mutating command in a wake-up condition, because conditions run outside the sandbox with no approval.

## References

- `references/fleet-files.md`: storage layout, setup, remote members, takeover, and templates for `RULES.md` and `LEAD.md`. Read at setup.
- `references/briefs.md`: spawning, the task brief, the permanent member's prompt, steering, the critic brief and the phase pipeline for large batches. Read before writing a brief.
- `references/members.md`: charters, check prompts, state files, wake-ups, sentinels, liveness, keepers and sub-leads, with skeletons. Read before starting or changing a permanent member.
- `references/risk.md`: change risk, mitigate first, monitoring that's proven to work, cutover gates and advance-approved rollback. Read before any high-risk change or cutover.
- `references/comms.md`: replies, morning packets, ship lists, trackers, and messages sent as the human. Read before writing any of them.
- `references/lessons.md`: what went wrong in the run this skill came from, and which rule answers each problem. Read when a rule seems too strict, or when explaining the process to someone.
- `scripts/fleet-status.py`: the lead's member table, with stale, failed and waiting members flagged. It is advisory and can't prove a member's wake-ups are healthy.
- `scripts/pr-sentinel.py`: a read-only PR sentinel for a keeper's `until.check`. It exits 0 on a material change, 1 when nothing changed and 2 on any error.
