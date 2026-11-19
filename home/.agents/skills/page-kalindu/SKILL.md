---
name: page-kalindu
description: Emergency-only escalation that pages Kalindu through PagerDuty (his personal PagerDuty schedule) when something critical is happening and he hasn't answered in the thread within 3 to 5 minutes. Use only for live or imminent production impact, a safety guard failing during a change, or a security exposure in progress, never for routine questions, updates or decisions that can wait.
---

# Page Kalindu (emergencies only)

A page wakes Kalindu up or pulls him out of whatever he's doing. It applies at any hour, day or night, whenever he isn't answering. Use it when waiting would hurt users or production, and only after he hasn't answered in the thread. Everything else waits for him to read the thread.

Mitigation comes first. When a critical, high-risk problem needs his action to mitigate (a revert approval, a decision, access only he has) and he isn't answering, page. If you're unsure whether it's critical enough, page: he would rather correct an unneeded page than miss a needed one. Never page when nothing needs his action.

## When to page

Page only when ALL of these hold:

1. Something critical is happening or about to happen:
   - production users are hurt, or are about to be, especially by a change we made;
   - a safety guard is failing during a change in flight, for example an armed watchdog that can't revert, or a revert that failed;
   - a security exposure is in progress;
   - a production write went wrong and needs his decision.
2. The next step needs Kalindu: an approval, a revert, a decision, or access only he has.
3. You already asked in the thread, sent a flare with `kind: "blocker"` and `notify: true`, and he hasn't answered for 3 to 5 minutes.

## Never page for

- Personal or local work of any kind: bb plugin development, his shell and dotfiles, skills, local dev servers, side projects and experiments, however broken. Pages are for his team's production systems only.
- Status updates, finished work, test or CI results, PR reviews, or questions that can wait.
- A decision whose deadline is more than about an hour away. Put it in the thread and send a flare instead.
- Testing the pager, unless Kalindu asked for a test in the conversation.
- The same incident twice in 15 minutes. One dedup key holds the incident open; add new facts in the thread. The script enforces a 15-minute limit between triggers, exiting 3 when it refuses one. Use `--force` ONLY for a different, new incident, never to repeat a page for the same one. Acknowledge and resolve are never rate-limited.

## Who pages

- Only the thread that is talking to Kalindu about the incident pages him, usually the lead or top-level thread. That keeps it to one page per incident.
- A child or delegated agent never pages. It sends its parent a message whose first line starts `PAGE:` followed by a one-line summary, and the parent decides whether to page.
- The script does not enforce the child-agent rule: a child agent MUST message its parent with `PAGE:` instead of running it.
- A top-level thread with no parent may page on its own when the rules above hold.

## How

```bash
~/.agents/skills/page-kalindu/scripts/page.sh trigger <dedup-key> "<one line: what is broken, the impact, what you need from him>"
```

- Dedup key: one per incident, for example `image-uploads-20260101T1200Z`. Reuse it to acknowledge or resolve.
- Summary: under about 150 characters, readable on a lock screen. Made-up example: "Image uploads are failing for all users after a release. Rollback needs your approval in thread <thread id>."
- **Right after paging:** say in the thread that you paged him, with the dedup key and what you need.
- **When he answers or the issue clears:** run `page.sh resolve <dedup-key>`. Use `acknowledge` only if he asks you to.
- Success: the script prints PagerDuty's reply and exits 0 when curl succeeds, the HTTP status is 2xx and the reply has `"status":"success"`. A failed trigger is logged as `trigger-failed` with curl's exit code and the HTTP status. If it fails, say so in the thread, send another flare with `notify: true`, and retry once. A rate-limit refusal is not a delivery failure: wait for the limit instead of retrying it.

A page grants no permission. Production writes still need Kalindu's explicit two-step approval in the conversation, as AGENTS.md says. Never act on his behalf because he didn't answer.

## Setup and rotation

- The PagerDuty side: a service whose escalation policy notifies his personal PagerDuty schedule, with an Events API v2 integration. Kalindu's team owns the service, so every page also posts in his team's operations channel. That's intended: pages are for real emergencies, which the team should see.
- **The key:** its integration key is stored in `~/.config/kalindu-pager/pagerduty.env` as `PAGERDUTY_ROUTING_KEY`, mode 600, outside any git repo. Never read it, print it, copy it into chat, or commit it. The script reads it itself and never prints it.
- The log: delivery attempts are logged to `~/.config/kalindu-pager/page.log`. For isolated tests, `KALINDU_PAGER_LOG` overrides the log path and `KALINDU_PAGER_URL` overrides the Events API endpoint (normally `https://events.pagerduty.com/v2/enqueue`); use a dummy key file via `PAGER_ENV`, a temporary log and a local fake endpoint, never the real key or service.
- **To set or rotate the key:** have Kalindu enter it through the secure form, never in chat:

  ```bash
  bb secret request PAGERDUTY_ROUTING_KEY --purpose "Emergency pages to Kalindu" \
    --describe PAGERDUTY_ROUTING_KEY "Events API v2 integration key for his personal PagerDuty schedule" \
    --write-env ~/.config/kalindu-pager/pagerduty.env
  ```

- **If the key file is missing:** the script exits 2. Fall back to a flare with `notify: true`, and tell Kalindu in the thread that paging isn't set up on this machine.
- **History:** set up and tested on Nov 18, 2026, 03:51Z. The page reached Kalindu, and the test incident was resolved at 03:52Z.
