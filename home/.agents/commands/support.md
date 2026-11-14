---
description: Investigate a Slack support request and recommend a grounded response
argument-hint: "<Slack URL> [context]"
---

Load the `support` skill and follow its instructions for: $ARGUMENTS

## Rules

- ALWAYS load the `cortex` skill and persist the investigation in one Cortex task
- Require a Slack permalink; if none is provided, ask for one
- Keep investigated systems read-only; Cortex task persistence and flares to the user are the only writes
- Judge urgency from the thread itself (a page, an incident channel, a firing alert, live merchant or buyer impact); when it looks critical or urgent, follow the skill's page mode without being told: flare an acknowledgement within two minutes, flare every material finding as it lands, and flare a validated fix without waiting for every minion
- If deeper investigation will likely take more than ten minutes, provide a provisional sample response BEFORE starting it (in page mode, as a flare)
- NEVER post the response to Slack; return a paste-ready recommendation for the user
- Cite the Slack thread and every material supporting query or source
- Return the Cortex task ID with the final recommendation
