# Talking to the human, and to everyone else

The human's attention is the fleet's scarcest resource. The common failures are updates that never arrive, packets too long to read, progress numbers that undersell the work, and paste-ready text that breaks when pasted.

## A reply

1. The first sentence is the answer, or the state in one line.
2. Then the evidence as a block or a few bullets: a table of streams, a list of steps, a verdict table.
3. Then what happens next and who does it.
4. Then what the human must decide, as questions (in the question panel on bb).
5. A link to the full file for anyone who wants detail.

Keep it to one screen. Don't recap what the human just said or list tool calls. Use the human's time zone. When several member reports arrive together, send one summary.

## Questions and approvals

- Batch questions, a recommended option first, with the context the human needs in each question. On bb, use the question panel. Elsewhere, number them in the reply so the human can answer by number.
- Keep working on what doesn't depend on the answer, and say briefly what is waiting on it.
- Ask for a gated action once, at the level it needs (`SKILL.md` Guardrail 2). A production change gets two questions: the first shows the exact command, target, effect, why and undo, and the second restates it immediately before running, for one run. Anything else gets one question with what, where, the effect and the undo, and the human's yes is final: don't confirm again before running.
- Never ask for what a grant in `RULES.md` or the human's own request already covers. When the same kind of action will come up again, offer a grant in the question, for example "Merge #412 and the three PRs after it once checks pass? This also covers queuing them again after a fix."
- When you act under a grant, say what you did in the next update ("merged #412 at 14:05"), not before.

## Morning packet and end-of-day summary

Write it before the human logs off, re-check the live state when they ask for it, and open with the short version.

```markdown
# Morning packet, <day>
Written <time>. States read from <sources> at <time>.

## The short version
1. <Most important thing the human must do, in one line.>
2. <Second.>
3. <Everything else is healthy or waiting on others.>

## Deploys and merges, in order
| Step | What | Revision | Where it stands | Check after |
| --- | --- | --- | --- | --- |
| 1 | <app or PR> | <sha or artifact> | <per target: merged, rolling, live> | <command that must pass> |

## Work streams
<One short paragraph or table row per stream: state, PRs, what's next.>

## Not ours, worth a look
## Running overnight
<Each permanent member: what it watches and when it next wakes.>
```

In chat, show the short version as a block and link the file. If the human says they don't want to read pages and pages, aim for about a screen.

## Ship list and deploys

The human asks "what can ship, in what order?" often. Keep `$FLEET/ship/SHIP-LIST.md` current and answer from it.

- Ours only. Delegated PRs never appear as ours to merge, even when we wrote them, they're approved and their checks pass. Show them separately as read-only.
- Group by what each needs: ready now, needs one thing (say what), the human decides, waiting on others, later (with the reason). A PR with failing CI or conflicts is not ready; fix it or say why it's blocked.
- For each deploy give the intended revision or artifact, the targets and their order, dependencies between deploys, the check before and after, and which revert comes first if it goes wrong.
- Before a deploy starts, confirm the intended changes are in the artifact being deployed. A deploy triggered from an older revision silently misses PRs merged after it.
- Verify the content on the first target before the rest roll, if the rollout can hold. If it can't, check the rollout's own gates beforehand, watch the earliest target, and name who aborts. Report each target as merged, rolling, live or released, and say "revision unverified" rather than assume.

## Trackers and boards

- Track what we own or must actively manage. Other teams' PRs crowd the view. A board for delegated work nobody acts on is noise.
- Archive a board or section when its work is done, and restore it if the work resumes. Keep finished items visible, folded, because they show progress.
- Group items the way the human thinks about them, for example by owning team and service, not by batch or date.
- Compute every number from a data file and show its source and time. Never type a number into a page.
- Progress numbers follow the five rules in `SKILL.md` (Talking to the human): a fixed baseline, a percentage for finished work only, in-flight work beside it, one headline per question, and a label on every number. Keep the headline's definition in a small data file, so it can change without touching the page.
- Show the size of the work through what was built, what moved and what's left, in the human's units. A bare "X of Y gone" can undersell months of work on the replacement, and "X of Y gone or in flight" can read as inflated. Neither is fixed by changing the ratio: say what was built in a sentence, and give the breakdown.

## Messages sent as the human

This covers chat messages, emails, comments on other teams' PRs and anything else other people will read under the human's name.

- Agents never post, react or send as the human. They write drafts, and a draft is saved under the human's name only after the human approves the exact text and destination. Save once per destination, because some tools can't list or delete drafts. Keep a ledger with one row per message, keyed by channel, thread and team: the exact text saved, save status, and the permalink once posted. Check the human can post in the channel before saving. If a save's result is unclear, check before retrying.
- Render repeated messages from a template and check them with a linter. The template holds the human's opener, closing line, links and tone. Build it as soon as the human corrects the format twice.
- Write plain text with real newlines and links in the destination's own format. Render the first batch with the destination's own formatter before saving. If a live test is needed, pilot one approved destination through the real save path, with the human's approval.
- Link the artifact the message refers to, such as the draft PR, on every item. Where there's no draft, say so plainly.
- Use the owner's own designated channel or thread: their registered or support channel, a thread you already have with them, or one they named. Check recent human activity there. Avoid bot and alert channels, and never guess. An owner's correction overrides the registry and goes into `RULES.md`.
- Ownership must be exact: at least two independent sources agree on the owning team, the people tagged are current, active members, and a second verifier checks every team and tag. Mark anything uncertain UNSURE and ask the human.
- Before contacting a team, reconcile everything for that team (what's live, earlier messages and drafts, their replies, work they already have in progress) and send one complete packet, so the same people aren't asked twice. Separate teams get separate messages, even in a shared channel.
- A delegation message gives a starting point, nothing more: what's changing and why, the draft to start from, how to get help, and "the timing is yours, sooner is better". No dates, and no decisions that belong to the owners.
- Short beats thorough. Teams know their systems better than we do, so don't justify with numbers they can read themselves.
- If a sent message turns out to be wrong, give the human a short correction to post in the same thread.
- When the human edits a draft before sending, record the edit and fold the pattern into the template. Record their style preferences in `RULES.md` so every member's text follows them.
