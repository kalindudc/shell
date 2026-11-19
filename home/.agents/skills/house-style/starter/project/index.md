# The new queue runs, three big senders are left.

Every service but fourteen sends its jobs to the new queue. Three of the fourteen send nine in ten of the old queue's jobs, and each has a plan. Invented example content.

## Where it stands

- Built: 14 clusters run the new queue, 9 of them in production across 3 regions. It has retries with a dead-letter queue, quotas for each tenant, a dashboard with a backlog alert, and a replay tool. Source: cluster inventory, 13 November 2026.
- Moved: 38 of 52 services; Billing, the first big one, since 4 November. 214 of 260 job types are off the old queue, and 9 of 16 cleanup PRs are merged. Owners have been asked about 9 idle job types. Sources: job audit and the PR board, 13 November 2026.
- Left: 3 services send 91% of the old queue's jobs (Search indexing, Mail and Exports), each with a plan. 6 smaller services are in progress and 5 not started.

| State | Services |
| --- | --- |
| Done | 38 |
| In progress | 6 |
| Not started | 5 |
| Needs a new path | 3 |

## Phases

1. Build the new queue: 5 of 5 done.
2. Move the services: 38 of 52 moved, 6 moving.
3. Move the big senders: 0 of 3, plans ready.
4. Switch off the old queue: after the last move.

## Where the jobs are

Share of the old queue's jobs, week to 13 November: Search indexing 54%, Mail 23%, Exports 14%, every other service 9%.

## Next

- 4 Nov, done: Billing moved, with no lost jobs.
- 20 Nov, now: Exports moves; its owner runs the approved plan.
- 2 Dec: Mail moves, after the holiday freeze lifts.
- 9 Dec: Search indexing moves, replays first, then live jobs.
- 16 Dec: the old queue switches off, read-only for a week, then removed.
