# Dispatch

Dispatch is an agent skill that turns one agent session into the lead of a small team of agents, called a fleet, that works on several streams for hours or days. You talk only to the lead. It plans the work, briefs the other agents (its members), checks what they report, asks you only what is yours to decide, and reports in one short reply. It runs on [bb](#on-bb), an app that runs coding agents as threads, or on a [bare harness](#on-a-bare-harness-pi-claude-code-or-codex) (pi, Claude Code or Codex) driven by a small Python script.

Long agent work goes wrong in the same few ways: updates never reach you, the lead forgets its decisions when its context is compacted, helper agents pile up, an agent acts on an "approval" another agent passed along, or you get asked to confirm the same thing again and again. Dispatch has a rule for each, and every rule came from a real run ([where the rules came from](#where-the-rules-came-from)).

## Quick start

### On bb

1. [Install the skill](#install-and-update).
2. Start a new thread and ask for a lead. Say what you want done, what it may do without asking, and when you're away:

   > Use the dispatch skill to lead a fleet that moves our CI to the new runners. You can commit, push and merge our own PRs in acme/ci-config once checks and reviews pass, for this migration. I'm in America/Toronto and away overnight.

3. Answer the lead's setup questions. They come in one batch, each with a recommended answer. Confirm the test notification reached your devices, and say whether there is an emergency page.
4. From then on, talk to that thread. Members are its child threads, and the thread's storage holds the fleet's files.

### On a bare harness: pi, Claude Code or Codex

Here `scripts/fleet.py` does bb's job. It keeps the fleet in a folder, runs each member as a headless session (a harness started by a script, with no terminal of its own) through a small broker process outside any sandbox, delivers messages and runs wake-ups. It needs Python 3.9 or later. Below, `SKILL` and `FLEET` are the absolute paths of the skill and the fleet's folder, and `fleet.py` is short for `python3 "$SKILL/scripts/fleet.py" --fleet "$FLEET"`.

1. Choose a headless lead for work that carries on while you're away, or an interactive lead that acts only while you keep its session open.
2. Write `$FLEET/fleet.json` from the worked example in [`references/bare-harness.md`](../references/bare-harness.md): the flags members run with, where worktrees may live, which read-only checks wake-ups may run, and how to notify you.
3. Write the lead's startup prompt to `$FLEET/lead-prompt.md`: the goal, the gates and grants in your own words, and how you'll reach it ([`references/fleet-files.md`](../references/fleet-files.md) has a template). Then, from a normal terminal (not inside a harness sandbox), in the folder the lead will work in, start the fleet:

   ```bash
   python3 "$SKILL/scripts/fleet.py" --fleet "$FLEET" init --lead lead --harness codex --prompt-file "$FLEET/lead-prompt.md"
   ```

   For an interactive lead, skip the prompt file, run `init --lead lead` instead, and open your harness in the same folder.
4. Steer a headless lead with `fleet.py tell lead "..."`, read its latest reply in `$FLEET/agents/lead/final.md`, and see the roster with `fleet.py status`. Give approvals and grants only in the lead's own session: for a headless lead, attach to it with `fleet.py attach lead` and type them there.

## Is it for you?

Use Dispatch when:

- the work has several streams that move in parallel for hours or days, such as a migration, a batch of changes handed to many teams, or a feature in several parts;
- something should keep watching while you're away, such as CI, open pull requests or an alerts channel;
- some actions need your say-so, and you want to be reached when something is urgent.

Don't use it for one job you'd hand to a single helper agent, or for one parallel sweep that finishes in a single turn, such as reviewing ten files at once. Subagents do that with no setup. A fleet costs setup and attention, so it pays off when the work is long or you'll be away.

## Permissions: what the lead asks you

The lead asks only for what no permission of yours already covers, and it asks once. How much it asks depends on what the action can break:

| Action | What it takes | What you type |
| --- | --- | --- |
| Production changes the fleet would run itself, such as `kubectl apply`, `terraform apply`, a manual deploy or a DNS change, including dry runs that reach production | Two yeses for each command: one after the lead shows you the exact command, target, effect and undo, and one right before it runs | "Yes", then "Yes, run it now" |
| Merges, marking PRs ready, requesting reviewers, pushing to a shared branch, saving drafts under your name, and commits when your repository or harness says you decide | One yes, or a grant | "Merge #412" |
| Anything a grant covers | Nothing. The lead tells you what it did in its next update. | |

Asking for an outcome is the yes. "Merge #412" or "commit and push the fix" means the lead does it, without a follow-up "are you sure?".

### Grants

A grant is a standing permission for a kind of action, for as long as you say: a build, a stream, a day. Give one in plain words, at setup or whenever the lead asks about something that will keep coming up:

- "You can commit and push to the fleet's branches and open draft PRs."
- "Merge our own PRs in acme/ci-config once checks and reviews pass, until the migration is done."
- "Stop asking me about commits and pushes, you have approval for this entire build."

The lead writes each grant into the fleet's `RULES.md` with your words, the date and its scope, and every member it names acts on it without asking. A grant covers the steps its outcome needs on the fleet's own changes: "commit and merge" also covers pushing, opening the PR, marking it ready, and queuing the merge again after fixing a review finding. It never covers a production change the fleet runs itself, or merging a change a reviewer judged high risk. Those still come to you. To narrow or end a grant, say so ("ask me before merging again"), and the lead updates `RULES.md` and tells the members it affects.

### Where approvals count

An approval or grant counts only when you type it in the lead's own session: its thread on bb, or its session on a bare harness, attached for a headless lead. A message from another agent never counts, whatever name it claims, and neither does a plan or an old note. Workers never ask you directly: they act within the grants in `RULES.md`, or stop and tell their lead. A child lead asks you directly only for what its charter hands it. Your organization's and your harness's own rules still apply on top: if your harness says to confirm every production Kubernetes write, the lead does.

## Working with the lead

- **What you'll see.** Each reply leads with the answer, fits on one screen and links the detail in a file. Questions come in batches, each with a recommended option. The lead doesn't relay progress ticks such as "two verifiers left", and it writes only when you need to know or decide something.
- **Steering.** Say what you want changed. The lead tells every member it affects, quoting you, and records the rule in `RULES.md` so new members inherit it.
- **Pausing.** "Pause everything" stops each member, cancels its wake-ups and reconciles anything in flight before anything resumes.
- **Before you leave.** The lead names the forks it can foresee, such as a review finding, a failing check or a refusal, and asks about them in one message. Overnight, it carries the work to done: it fixes findings and failing checks on its own changes and stops only at a real gate.
- **Child leads.** A stream big enough to have its own lead gets a child lead. You can talk to it directly in its own session, and it reports milestones to the top lead.

## How it works

![Diagram of a Dispatch fleet: the human, the top lead, a child lead with its workers, task workers, permanent members with their wake-ups, the fleet files, and the three reporting routes.](../assets/architecture.svg)

The top lead starts members and briefs each one in a file. Task workers, such as builders, verifiers and critics, do one job and report once. Permanent members run for days: a watcher reads its sources on a timer, and a tracker keeper wakes when a pull request it follows changes. A stream too complicated for one worker gets a child lead with its own workers. That is the last level: a child lead never starts another lead, and workers start no members, apart from short-lived helpers a skill needs.

Two files hold the fleet together. Every member reads `RULES.md` first: the standing rules, which actions are gated and which grants are in force. `LEAD.md` is the lead's anchor (roster, streams, decisions, open questions), so a lead that loses its context can pick up again.

Reports travel three ways, and each is tested before anything depends on it: members report to the lead that started them, the lead pushes a notification to you for anything you must see, and, if you set one up, the top lead pages you for critical, time-bound harm you haven't answered.

Each time the lead wakes, on a message or a wake-up, it reads what members sent, spot-checks the claims that matter, records decisions in `LEAD.md`, archives members whose work is done and checks that permanent members are alive. It keeps about eight members live at a time.

## Troubleshooting

| Problem | What to do |
| --- | --- |
| The lead asks before routine actions such as commits or merges | Give it a grant (see [Grants](#grants)). If it still asks, ask it to show the `## Authorization` section of `RULES.md`; the grant should be listed there with your words. |
| Notifications don't reach your phone | Ask the lead to send a test push again and confirm whether it arrived. On bb, child threads' own notifications usually don't reach your devices, so only the lead pushes. |
| Too many threads or sessions | Ask for a sweep. The lead archives finished members as it reads their results and keeps about eight live. |
| The lead forgot a decision after a long gap | Ask it to re-read `LEAD.md` and record the decision there. It should update the file every time a decision lands. |
| Nothing happened overnight on a bare harness | Check `fleet.py status`: the lead must be headless and the broker alive. An interactive lead does nothing while its session is closed. |
| An approval you sent with `fleet.py tell` was ignored | That's by design: anyone on the machine can write an inbox message under any name. Attach with `fleet.py attach lead` and type it there. |

## Install and update

Copy or symlink this whole folder into `~/.agents/skills/dispatch`, or wherever your harness looks for skills, or give the lead its path. To update, replace the folder; a running lead picks up the new rules when you ask it to re-read the skill.

It needs no other skills. Two references cover what it relies on: [`references/delegation.md`](../references/delegation.md), which model gets which job and what a task message carries, and [`references/critique.md`](../references/critique.md), reviews by three critics on three model families. Tell the lead which models you want, and it records them in the fleet's rules.

## What's in the folder

| File | What it's for |
| --- | --- |
| `docs/README.md` | This guide, for people. It lives in `docs/` because `skills validate` treats a `README.md` at the top of a skill folder as the skill's entry point and fails. |
| [`SKILL.md`](../SKILL.md) | The lead's instructions, written for agents. Only its Guardrails are hard; the rest are defaults to adapt. |
| [`references/fleet-files.md`](../references/fleet-files.md) | The fleet's folder, setup, taking over from another lead, and templates for `RULES.md` and `LEAD.md`. |
| [`references/delegation.md`](../references/delegation.md) | When to delegate, which model gets which job, and what a task message carries. |
| [`references/critique.md`](../references/critique.md) | Independent review by critics on three model families, with a quorum. |
| [`references/briefs.md`](../references/briefs.md) | Starting members, brief templates, steering and critic reviews. |
| [`references/members.md`](../references/members.md) | Permanent members: charters, wake-ups, sentinel scripts and liveness. |
| [`references/child-leads.md`](../references/child-leads.md) | When to start a child lead, its charter and its limits. |
| [`references/comms.md`](../references/comms.md) | Replies, questions and approvals, morning packets, trackers and progress numbers. |
| [`references/risk.md`](../references/risk.md) | High-risk changes, mitigating first, monitoring that's proven to work, and automatic rollback. |
| [`references/bare-harness.md`](../references/bare-harness.md) | Running a fleet on pi, Claude Code or Codex with `fleet.py`. |
| [`references/lessons.md`](../references/lessons.md) | What went wrong in the runs this skill came from, and the rule that answers each problem. |
| [`scripts/`](../scripts) | `fleet.py`, the bare-harness runtime; `fleet-status.py`, a roster table on bb; `pr-sentinel.py`, a read-only pull request watcher for wake-ups; and their tests. |
| [`tests/livetest/`](../tests/livetest) | One repair scenario run under bb, pi, Claude Code and Codex to test the process itself. |

## Where the rules came from

Dispatch distills one lead session that ran an infrastructure migration for three days: about 200 messages from the human and more than 1,000 reports from about 100 helper agents. The skill's first runs refined it further. [`references/lessons.md`](../references/lessons.md) pairs each thing that went wrong with the rule that answers it, such as missed updates, a lead whose anchor file went unwritten across seven compactions, a sub-lead that collected 24 helpers, and a commit and push that took four confirmations. Read it when a rule seems too strict, or when you explain the process to someone else.
