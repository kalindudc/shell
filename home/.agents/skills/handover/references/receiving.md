# Receiving side (/pickup): resume from a handover task

Loaded from SKILL.md when `/pickup <task-id>` runs. Goal: take a handover
cortex task id, consume its brief, orient in the repo, and continue the work —
in a brand-new session with no prior context.

### Procedure

1. Require a task id (the `/pickup` argument). If none was given, list
   candidates and ask which to resume — do NOT guess:
   ```bash
   cortex ls -t handover            # optionally scope with: -l <lane>
   ```

2. Pull the task and read the brief. `.task.body` is the brief; `.updates` is
   its history:
   ```bash
   cortex show <id> --json | jq -r '.task.title, .task.status, (.task.tags|join(",")), "----", .task.body'
   ```
   If `.task.tags` does not include `handover`, WARN the user and continue only
   on their confirmation — the body may not be a handover brief.

3. Consume the brief in full. Prioritize: section 4 (Environment & Resume
   Runbook), 9 (Next Steps), 10 (Open Questions / Blockers / Risks), and 8
   (Rejected alternatives — do NOT re-explore those dead ends).

4. Orient in the environment (READ-ONLY): confirm you are in the repo root from
   section 4 (`cd` there if needed), then run the brief's "first orientation
   commands" — typically `git status`, `git branch --show-current`, `git diff`,
   and reading the key files listed in sections 5/7.

5. Reconcile brief vs reality. The repo may have changed since the brief was
   written (commits landed, branch switched, files moved). CURRENT REPO STATE
   WINS over the brief. Explicitly flag every material discrepancy to the user.

6. Restate the mission and the immediate next step in your own words, then
   CONFIRM the plan with the user before making any changes.

7. Link the resumption for resumability + audit trail — post an update via the
   `cortex_update` TOOL (this maps the NEW session to the task):
   ```
   cortex_update({ task_id: <id>, message: "resumed in a new session; continuing from Next Steps" })
   ```
   As work proceeds, post further updates; flip status to `done` when the
   mission is complete, or `blocked` with the reason if you get stuck.

8. Execute section 9 (Next Steps) in order, honoring the constraints in
   section 3 and the user's git protocol (NEVER commit unless asked).

### Rules (receiving side)

- Ground every claim in the task body + the live repo; NEVER invent state.
- When brief and repo disagree, TRUST the repo and surface the delta.
- Confirm before the first mutating action.
- Attribute via the `cortex_update` tool (resumable), not `cortex update --as`.
- Respect section 8 — do not re-explore rejected approaches.

### Return to the user (receiving side)

**Resumed from handover #<id>.**
- **Mission:** <one line from section 1>
- **Repo state vs brief:** <in sync / list discrepancies>
- **Immediate next step:** <the section-9 step you will do first>
- **Confirm?** <the one question you need answered before you start changing things>
