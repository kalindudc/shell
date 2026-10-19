---
description: Review and improve a skill based on accumulated usage observations
---

Load the `improve-skills` skill and follow its instructions to improve: $ARGUMENTS

Use a provided skill target directly. If no target or explicit batch/all request is supplied, ask which skill or batch once; do not start a fleet-wide scan by default.

## Explicit batch mode

1. For a user-requested batch, inspect only the requested skill set and its relevant observations/evaluation evidence.
2. Collect the skill's slow-loop proposals before presenting them; do not apply changes while collecting.
3. Present a grouped list with the skill, proposed change, evidence, and rationale.
4. The user accepts, rejects, or modifies each proposal; apply only approved changes.

## Rules

- Load `improve-skills`; only run the all-skills batch when the user requests batch/all.
- Follow the selected skill's approval and ownership rules rather than duplicating its workflow.
- In an explicit batch, collect proposals before asking for decisions; do not interrupt once per skill.
