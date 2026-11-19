# 9 of 16 cleanup PRs merged, seven still open.

Every pull request that moves a service off the old queue or removes its code, grouped by team. Invented example content. Updated 13 November 2026, 14:05.

| Stage | PRs |
| --- | --- |
| Draft | 1 |
| Open | 4 |
| Approved | 2 |
| Merged | 9 |

## Billing, all merged

- #1002 Move invoice jobs to the new queue: merged
- #1007 Move payout jobs: merged
- #1011 Remove old-queue clients: merged
- #1015 Drop the old retry table: merged

## Mail

- #1043 Send receipts through the new queue: open
- #1051 Remove old-queue retries: open
- #1038 Add the dead-letter alert: approved
- #1012 Move digest emails: merged
- #1019 Move bounce handling: merged
- #1024 Move unsubscribe jobs: merged

## Search

- #1060 Replay indexing jobs on the new queue: draft
- #1057 Split the indexing worker: open
- #1049 Rate-limit the reindex job: open
- #1031 Add indexing quotas: approved
- #1004 Move suggestion jobs: merged
- #1009 Move synonym jobs: merged

## Rollouts

- Billing, done: both queues took jobs on 28 Oct, workers read the new queue on 31 Oct, the old queue stopped on 4 Nov.
- Exports, now: plan approved 12 Nov; both queues take jobs on 20 Nov; workers move on 21 Nov; the old queue stops on 25 Nov.
