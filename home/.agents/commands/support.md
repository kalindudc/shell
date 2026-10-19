---
description: Investigate a Slack support request and recommend a grounded response
argument-hint: "<Slack URL> [context]"
---

Load the `support` skill and follow its instructions for: $ARGUMENTS

## Rules

- ALWAYS load the `cortex` skill and persist the investigation in one Cortex task
- Require a Slack permalink; if none is provided, ask for one
- Keep investigated systems read-only; Cortex task persistence is the only write
- If deeper investigation will likely take more than ten minutes, provide a provisional sample response BEFORE starting it
- NEVER post the response to Slack; return a paste-ready recommendation for the user
- Cite the Slack thread and every material supporting query or source
- Return the Cortex task ID with the final recommendation
