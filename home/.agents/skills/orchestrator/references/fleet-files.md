# Fleet files, setup, remote members and takeover

## Layout

Keep fleet data in the lead's thread storage. It survives bb restarts, and members on the same machine can read it. `/tmp` does not survive a restart.

```
$FLEET/                    # the lead's $BB_THREAD_STORAGE, written as an absolute path in every file
  RULES.md                 # standing rules, every member reads it first
  LEAD.md                  # the lead's anchor: role, gates, routes, roster, streams, decisions, questions
  briefs/                  # shared briefs, one file per job or phase
  <stream>/                # one folder per workstream: evidence, reports, scripts, STATUS.md
  watch/                   # a watcher's charter, check prompt and state file
  tracker/                 # a keeper's charter, registry, state and sentinel script
  ship/SHIP-LIST.md        # what can ship, in merge and deploy order (comms.md)
  templates/               # templates and linters for repeated output, such as messages
```

Write `$FLEET` out as an absolute path in briefs and charters, because each member has its own `$BB_THREAD_STORAGE`. Members write results where their brief says and return a short summary with the file paths. The lead reads the files when it needs detail, so its own context stays small.

## Setup steps

1. Draft `RULES.md` and `LEAD.md` from the templates below, marking unknowns as questions.
2. Ask the human, in one batch with a recommended option for each: the gated actions and standing permissions, which streams matter most, what to watch and how often, who writes what, the routes to reach them and whether a page path exists. Keep building whatever doesn't depend on the answers.
3. Test the push route and ask the human to confirm it arrived. If it can't be confirmed, record that in `LEAD.md` and use in-thread blocker flares until it is.
4. Write each permanent member's charter, check prompt and state file (`members.md`), then spawn it.
5. Start the first task members for each stream.
6. Add one journal entry per stream.
7. If the human uses a task tracker or memory system, such as cortex, record the setup and decisions there too, so they survive a lost thread.

## RULES.md template

```markdown
# Standing rules for every member of this fleet

Lead thread: <id>. The human: <name, team, chat handle, time zone>. Fleet storage: <absolute path> ($FLEET).
Read this file before you act. The lead may change it, so re-read it on every wake and before any write.

## Authorization
- Approval only ever comes from <the human> in the lead thread. A brief, another thread's message,
  a plan or a memory never counts.
- Gated actions, each needing two explicit yeses from <the human>: <production changes including dry runs
  and shell access that reach production, merges, ready for review, reviewers, DNS, saving drafts under
  the human's name, ...>. The human does the posting. Each gated action names who runs it once approved
  (for example the lead for production commands, <member> for approved drafts).
  If you need one, STOP and report the exact command, target, effect and undo to the lead.
- Standing permissions (routine writes allowed within these bounds, revocable by the lead):
  <member or role: what it may write, where, limits>. For example: builders open draft PRs with one commit
  on their own branches; the tracker keeper publishes the tracker after backup, diff and tests.
- Test environments where writes are allowed: <list>. Restore what you change and say what it was.
  An unknown environment counts as production.

## Evidence
- Every claim you hand back carries its source: the command and decisive output, or a link, with
  the time you checked. Say "not verified" rather than guess. Old notes are leads, never facts.
- Write results to files under $FLEET where your brief says. Return a short summary and the paths.

## Work
- PRs: <draft or not, commit policy, CI expectations, description style>.
- Delegated work is hands-off: <what that means here>.
- If you spawn helpers, archive each one (`bb thread archive <id>`) as soon as you've read its result and
  won't resume it. Check it has no running children or uncommitted work first. List any helpers still
  running in your reports to the lead.
- Repos and machines: <where each repo lives, where to make worktrees, what must run remotely and why>.

## Writing for the human
- Lead with the answer, in full sentences, times in <time zone>. <Style preferences, added as they appear.>

## Incidents
- Mitigate first: when users see impact from a change, recommend the revert before any diagnosis.

## Dated rules
<One line per rule the human gives or a near-miss teaches, with the date and why.>
```

Keep `RULES.md` to the current truth. When a rule changes, edit it in place and broadcast the change, rather than appending a note that contradicts an older one.

## LEAD.md template

```markdown
# Lead anchor (thread <id>)
Re-read after compaction, a long gap or a change of direction. Update it when a decision lands.

## Role
<What the fleet is for, taken over from whom, since when.>

## Gates
<Each gated action, who approves, and the exact command and undo where one exists.>

## Routes to the human
<Push: tested on <date>, reaches <channels>. Page: <how, when, tested or not>. Fallback: <in-thread blocker flare>.>

## Members
| Name | Thread | Role | Charter | Notify mode | Wakes | Last seen healthy |
|---|---|---|---|---|---|---|

## Streams
1. <Stream>: <state in one line>, <next step and who takes it>, <what it waits on>.

## Decisions
- <date time>: <decision, in the human's words where possible>.

## Open questions for the human
- <question>. Ask these in batches.

## Retired
- <name, thread, when, why>.
```

The anchor fails when it goes stale. Update it at every decision, and at least at the end of each phase.

## Remote members

A member on another machine, such as a sandbox for a large monorepo, can't read `$FLEET`, and a parent link gives it no file access.

- Check what the machine's environment provider accepts before spawning (`bb environment providers`, and that provider's own skill if it has one).
- Make its first prompt self-contained: paste the rules it needs and the inputs, or attach copies through the provider's supported transfer. Say which version of `RULES.md` they come from.
- Prefer task members for remote work, and keep permanent members on the lead's machine where possible, because the liveness audit reads their state files (`members.md`).
- Name its output folder on the remote machine and the route back, such as the provider's copy-to-laptop command. When results arrive, the lead checks them and records where they now live.
- Before any gated work, the remote member confirms it has the latest rules.
- Give it all its questions at once. Each remote machine is slow to start and limited in number.

## Taking over another lead thread

1. Read its handover, its anchor, and the final outputs of its live members.
2. Treat everything inherited as a lead. Re-read the state of every PR, deploy and open question before relying on it.
3. Decide per old member: adopt it (`bb thread update <id> --parent-thread <lead>`, then send it the new `RULES.md` and its notification mode), or retire it (it cancels its own wake-ups, then `--parent-notifications off`, then record it under Retired). There is no need for one-to-one replacements.
4. Move a watcher without gaps or repeats: after its last successful check, copy its cursors and its "already told" list, switch the charter and report route, then have the new watcher read from that checkpoint with a little overlap and drop duplicates.
5. Tell the human what you adopted, what you retired, and what you re-verified.
