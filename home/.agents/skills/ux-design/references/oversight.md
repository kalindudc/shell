# Oversight UIs: one person supervising agents, jobs or other people's work

Read this when the UI shows work the person did not do themselves: agent threads, tickets worked by agents, pipelines, review queues. These are defaults for supervision tools, not rules for every product; the rails in `SKILL.md` still apply. No study says how many agent threads one person can supervise; every fleet-size number here is a hypothesis carried over from neighbouring fields (alarm management, code review, working memory, queueing) and is marked as such. Research gathered 2026-11-10.

## Situation awareness (Endsley)

Three levels: perceive the state, understand what it means for the goal, project what happens next. Endsley's design guidance: present comprehension and projection, not raw data; organise the display around the person's goals; keep an overview of everything visible at all times.

- Every row of work shows its state, how long it has been in that state, and whose move it is. Check: those three fields on every row, in a fixed position.
- State says what it means for the goal ("Blocked: needs your call on the migration order"), not what a tool did ("ran bash"). Check: sample ten rows; none leads with a tool name, a stack trace or a token count.
- Top-level groups map to the person's decisions, never to agent internals (worker, reviewer, model). A good default is by whose move it is, in one order on every surface: needs you, failed, ready for you, working, waiting on others or paused, done (folded). Change the order when the person's priorities differ, and keep it the same everywhere.
- Show projection: what is about to block, what a decision unblocks ("unblocks 3 tickets"), how much review is coming.
- The overview stays on screen while one item is open (a split view, or counts in a persistent header). Check: open any detail at 1280 px; the counts and the needs-you queue are still visible.
- Few named modes, in a fixed place, with changes announced in the activity history. Mode confusion grows with modes the UI does not help track (Sarter and Woods 1995).
- Show intent before a consequential action and the result after it, so the automation never surprises: a plan before work, a diff and summary after, and anything done that was not in the plan called out.
- Keep the person active at defined gates (approve a plan, review a change). Pure passive watching erodes awareness (Endsley and Kiris 1995, out-of-the-loop).

## The needs-you queue

Process-plant alarm management (ISA-18.2, EEMUA 191) is the best evidence on how much interruption one operator can take.

- Only items that need a timely human decision enter the queue. Status changes that need nothing go to the history. Check: each item type names the decision and the cost of delay; types with neither are demoted.
- Each item stands alone and is answerable in one action: what is asked, why, the options, the recommendation, what it changes, and what happens meanwhile. Pre-select the recommendation only when the choice is low-risk and easy to undo; for a consequential one, show it but ask for an explicit choice. A reader with no history can act quickly (aim for under 30 seconds).
- One root cause is one item: one blocked dependency that stalls five tickets shows as one item that names the five.
- Oldest wait first, with its age. Queue depth and oldest age are the two headline numbers.
- Budget the rate: about six items an hour across all priorities is the plant benchmark for one operator (EEMUA via secondary sources; a hypothesis for agent work); a flood is more than ten in ten minutes. Priorities skew about 5% high, 15% medium, 80% low (HSE quoting EEMUA).
- No push notification by default except the highest priority; the rest waits in the queue and shows as a count in the periphery (calm technology, Weiser and Brown; interruptions raise stress, Mark et al. CHI 2008). The queue is the source of truth: nothing exists only in a toast.
- Snooze or set aside leaves a visible count and comes back.
- "Next item" moves through the queue with each item's context loaded, so the cost of switching is paid once per batch. Keyboard: J and K to move, number keys to pick an option, Enter to answer, scoped to the page and ignored while typing.
- Track repeat offenders: the most frequent item types get fixed at the source (agent instructions, thresholds), not muted.

## Review capacity

- Reviewers find defects well in 200 to 400 lines at a time, under 500 lines an hour, for at most 60 to 90 minutes (SmartBear and Cisco study). Show the size of each review item (lines, files) and flag anything over 400 lines.
- Review is usually the constraint, not agent speed. By Little's law (L = λW), if work arrives faster than the person clears it, the queue grows without bound (derived example: 30 PRs a day against a capacity near 9). Show review load beside agent progress, and cap work awaiting review rather than adding dashboards.
- Every change arrives annotated: what changed, why, where to look first, what was not done, how it was tested.
- Avoid "approve all" across diffs unless the product already allows it and each item was reviewed.
- Batch work so one person can hold it: about four chunks of working memory (Cowan); a phase or batch of about eight items in two or three lanes is holdable, forty is not (derived).

## Dependency pictures

- Default to the focus item plus one hop, the rest folded into counts; expand on demand. Around seven nodes by default (derived from working memory; no empirical node limit exists).
- Edge crossings hurt graph reading more than anything else (Purchase 1997; Ware et al. 2002). Lay a DAG out in layers, left to right, with as few crossings as the graph allows and no acute ones; not every graph can be drawn without crossings, so bound what is shown instead.
- Every picture has a list beside it or one click away (sorted by what blocks the most), so a dense drawing is never the only way in.

## Human and AI (Amershi et al. CHI 2019; Google PAIR)

- Say what the agent can do and how well, before it starts.
- Pause, redirect and stop are close to hand wherever the product allows them; propose them where it does not, rather than adding them silently.
- When unsure, the agent asks; the ask is an explicit "waiting for you" state, distinct from error, idle and stale.
- Every result links to its reasons (the plan step, the log, the thread) and carries evidence (checks run, screenshots, commits).
- Before a consequential action, the control says what it will do to the world ("Merge into main: deploys to production").
- Announce changes to agent behaviour, model or autonomy in the history.
- Agents never approve or merge their own work; the UI shows who holds that permission.
- Stale is a state: an item with no activity for a stated time is flagged, not shown as running.

## A worked check for a project page

For each surface, answer in one line with evidence:

1. What needs me, and what does answering unblock? (perception and projection)
2. Is the work on track, and what does it need? (comprehension)
3. What happened since I last looked? (history, newest first, who in bold, time on the right, "N earlier" folded)
4. What is waiting on someone else, and for how long?
5. How much review is coming my way?
