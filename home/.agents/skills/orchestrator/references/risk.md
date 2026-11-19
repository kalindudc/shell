# Change risk, incidents and automatic rollback

Everything here is a default, except where it restates a Guardrail from `SKILL.md`. The numbers come from an HTTP proxy cutover. Adapt each item to the system's own failure modes (a queue has lag, ordering, idempotency and backlog drain, not request rates), and mark an item "not applicable" with a reason rather than leaving it unmet. A platform's own requirements are never waived here.

## Change risk

- A change is either high risk or not. There are no other levels.
- The reviewer decides, not the builder. The reviewer is the critics or the human. The builder hands over a confidence statement that says what was verified and what wasn't. A bare "95%" isn't one. When unsure, call it high risk.
- High risk usually means shared or fleet-wide config, quotas and limits, admission or policy rules, anything that reaches many targets at once, traffic cutovers for high-traffic services, and edits to long-lived objects that stay in place. This is guidance for the reviewer, not a checklist. A small, well-understood cutover can be judged not high risk.

A high-risk change also needs each of these, with an artifact in the PR or under `$FLEET`:

1. Pre-mortem: "a week from now this broke production; how?" List the defaults, reconcilers, admission rules, quotas and other teams' deploys the change meets, and how we'd notice each one.
2. Target census: every target the change lands on, read live, with each pre-mortem assumption checked there.
3. Critics: three critics on three model families try to break it, working from the pre-mortem (`briefs.md`), with a second pass after fixes. Their findings are closed, or waived by the human, before the PR is ready.
4. Rehearsal at production shape in a test environment, with production-like load and each kind of target represented.
5. Detection first: an alert and a dashboard for the pre-mortem's failure modes, proven to work (below), live before exposure.
6. Progressive exposure: one canary target per kind, soaked, then the rest. Move traffic in steps. If a ramp is impossible, write down why, the residual risk, the abort conditions and who approved the exception.
7. Mitigation ready: written rollback triggers, a tested revert or watchdog, and manual revert steps (below).

Overlapping high-risk production exposures go one at a time: soak and verify one before the next reaches production. Research, builds and reviews can run in parallel. Repairing a change that left things unstable is mitigation, not a new change. If the human's timeline can't fit serial exposure, say so at setup and propose batches.

## Mitigate first

- When users see impact from a change, revert it, roll it back or move traffic back to the last stable setup before any root-cause work or fix forward.
- When a rollback trigger holds or a user reports impact, recommend the mitigation. Never recommend "investigate first" while a tested, cheap revert exists.
- Diagnosis traps seen in practice: a coincident deploy is not an explanation, one quiet minute is not recovery, and the component's own stats (a proxy's admin endpoint, a database's own counters) come before any theory.
- Name a read-only evidence collector before a risky change. During mitigation it captures what will expire (logs, stats dumps, links with exact time windows) without delaying the revert.
- A fix forward ships only from a stable setup, as its own change, under the risk rules above.

## Monitoring that's proven to work

- Measure what clients receive at the new path, not only what the backend reports. A backend-only metric can't see errors the new layer generates itself.
- Watch saturation against limits: connections against the maximum, pending work, overflow, memory against its threshold. Put the old path's numbers beside the new path's.
- Prove each panel and alert that a decision depends on: a verifier shows it with real traffic in the exact filters and time window, on one healthy path and one known failure (a test or a recorded incident).
- Empty, stale, partial or inaccessible data is unknown, never zero and never clean. Name a second client-facing source, and fail the readiness gate if coverage can't be established.
- Scripts state the window they really cover. A log command asked for ten minutes that returns three, because of log rotation, must say three.
- Push on trends, not only on a fixed failure list.

## Change windows

- Checks every minute for the first 30 minutes, a chat watcher reading the change's threads every 1 to 2 minutes, and an immediate push on any user report of errors or slowness.
- One owner for the change's comms, posting at the change, at the first anomaly, at each decision and at the all-clear.
- No unrelated deploys to the same systems during the window and its first hour.

## Default evidence gate for a high-risk cutover

For a cutover the reviewer judged not high risk, a short check is enough: the targets, how you'll verify from the client side, and a tested revert. Any authorization it needs still applies.

Don't show a high-risk cutover to the human as ready until each item has evidence (command or link, decisive numbers and time) in `$FLEET/<service>/GATE.md`. Unknown means not met, unless marked not applicable with a reason. Functional checks are necessary and never sufficient.

1. Old-path load: peaks over at least a week, long-lived work (connections, streams, slow consumers), latency or lag percentiles, and the busiest hour. Name the service's long-lived features from its code.
2. New-path limits: every limit the new path enforces, its replicas and disruption budget, memory and overload thresholds.
3. Headroom with one instance lost, against those limits.
4. Default parity: every default on the new path that bounds the work, compared with what the old path does.
5. Capacity proof in a test environment above the measured peak (1.25 times worked for a proxy), with one instance lost and one app rollout during the load. "It has run in staging for days" is not a capacity proof.
6. A dashboard and an alert, proven as above, linked before the cut.
7. Rollback triggers, the revert, a tested watchdog if one is used, and manual revert steps.
8. A ramp with steps and holds, or the written exception above.
9. A deploy freeze for the window, agreed with the service's owner.
10. The old path stays live until a full peak has passed on the new one.
11. A watcher brief and a comms owner.
12. The permissions the revert needs are held, and verified, for the whole window.
13. The human sees this gate, every item with its evidence, before the first step of the approval.

## Revert and advance-approved automatic rollback

Every risky change has manual revert steps that someone other than the human can run: prerequisites, the exact target and its expected live state, the command, how to verify the revert from the client side, and who to hand to if it fails. Name that backup operator before the window and confirm they have the access.

An automatic revert takes detection and diagnosis out of the path, which is where most of the time goes. It fits the two-yes rule only if it's narrow:

1. First yes, before the change: the human approves one exact revert command at a pinned revision, the triggers with thresholds and durations, the signals the watchdog reads, the window (absolute start and end with time zone), and the undo.
2. Second yes, right before arming: the lead restates all of that and the human confirms.
3. The watchdog is a deterministic script run from the lead's environment, never a child's, and never as a wake-up condition. It checks its credentials, signal coverage and target state before arming, periodically while armed, and before firing. If any of them doesn't match, it disarms without running anything, alerts the lead, and the backup operator takes over.
4. It runs the revert at most once, logs, pushes a notification and exits. It disarms at the end of the window, after it fires, or when the human says so. Extending the window, re-arming the next day, a changed command, or a failed or unclear attempt each need a fresh two-yes approval.
5. Test it first in a test environment: one run where a real trigger must fire it, and a quiet hour where it must not. Then run it in shadow mode, printing "would revert", against real traffic to check the thresholds.
6. Record armed and disarmed in `LEAD.md`, and verify any revert it ran independently.

## Learning

- Every near-miss becomes a rule in `RULES.md` the same day.
- After an incident, mitigate, stabilize, then send a retro member (`briefs.md`) with the collected evidence. Feed its rule changes into `RULES.md` and its watcher lessons into the briefs.
