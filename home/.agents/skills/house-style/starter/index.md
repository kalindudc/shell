# One cache, every build.

Every CI job downloads the same dependencies before it does anything useful.
One shared, read-only cache would cut a typical build from nine minutes to
under five.

This is the plain text of [the proposal](index.html), without its drawings. Its status page is [overview.md](overview.md).
- Status: piloting on two of five repositories
- Asking: each repository's owner to approve its switch
- Owner: the build platform team
- Updated: 13 November 2026

The content is an invented example.

## 01 / The problem: half of every build is a download

A typical build spends four of its nine minutes fetching packages it fetched
an hour ago. Every job starts from an empty disk, so every job pays again,
and the queue behind it waits too.

The fix is not a faster network. It is not downloading the same bytes at all.

Where a typical build's nine minutes go:

| Phase | Time |
| --- | --- |
| Fetch packages | 4:10 |
| Compile | 2:30 |
| Test | 2:00 |
| Upload | 0:20 |

## 02 / The idea: fetch once, read everywhere

A cache beside the runners holds every package a build has asked for. Jobs
read from it and never write to it, so one bad job cannot poison another's
build. Only the cache talks to the registry.

- Today: each job pulls the same packages from the registry, about 2 GB a job.
- Next: jobs read a nearby cache they cannot change, and only the cache fetches.

> We spend more time waiting for the download than for the tests.
> (An on-call engineer, in the pilot)

## 03 / What it costs: small to run, quick to undo

The cache is one service and a disk per region. Turning it off sends jobs
back to the registry, so a bad day costs speed, never correctness.

- 4:40 minutes: a typical build with the cache, down from nine minutes.
- 96%: package reads served by the cache after its first day.
- 1 service: to run in each region, with a disk sized to a week of packages.

Why not cache inside each runner: runners are thrown away after each job, so
a local cache starts empty every time. Keeping runners alive to keep their
caches would cost more than one shared cache, and would let jobs see each
other's leftovers.

## 04 / Where it stands: two repositories in, three to go

The pilot runs on the two busiest repositories. The rest move once a week of
the pilot shows no wrong builds; each owner only approves the switch.

| Repository | State | Build | Waits on |
| --- | --- | --- | --- |
| storefront | On | 4:35 | nothing |
| checkout | On | 4:50 | nothing |
| admin | Next | 9:10 | the pilot's week |
| payments | Planned | 8:40 | its owner's approval |
| search | Blocked | 11:05 | a private registry |

## 05 / Still open: what I don't know yet, most pressing first

Two questions decide when the last repositories move. Neither blocks the pilot.

- Private registries (open): search pulls from a registry the cache cannot
  reach yet. Settled once the registry team grants it read access.
- Disk size per region (unmeasured): a week of packages fits today. Settled
  by a month of growth figures from the pilot.
