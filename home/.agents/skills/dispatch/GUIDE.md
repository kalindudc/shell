# Dispatch

Dispatch is an agent skill that turns one agent session into the lead of a small team of agents, called a fleet, that works on several streams for hours or days. The lead plans, briefs the other agents (its members), checks what they report and holds every approval, while the members do the work. You read one short reply and decide only what is yours to decide. It runs on bb, an app that runs coding agents as threads, or on a bare harness (pi, Claude Code or Codex) driven by a small Python script.

Long agent work goes wrong in the same few ways: updates never reach you, the lead forgets its decisions when its context is compacted, helper agents pile up, and an agent acts on an "approval" another agent passed along. Dispatch has a rule for each, and every rule came from a real run ([where the rules came from](#where-the-rules-came-from)).

## Is it for you?

Use Dispatch when:

- the work has several streams that move in parallel for hours or days, such as a migration, a batch of changes handed to many teams, or a feature in several parts;
- something should keep watching while you are away, such as CI, open pull requests or an alerts channel;
- some actions need your explicit approval, and you want to be reached when something is urgent.

Don't use it for one job you would hand to a single helper agent (the `delegation` skill covers that), or for one parallel sweep that finishes in a single turn, such as reviewing ten files at once; subagents do that with no setup. A fleet costs setup and attention, so it pays off when the work is long or you will be away.

## What a fleet looks like

![Diagram of a Dispatch fleet: the human, the top lead, a child lead with its workers, task workers, permanent members with their wake-ups, the fleet files, and the three reporting routes.](assets/architecture.svg)

You talk to one agent, the top lead, and an approval counts only when you type it in its session, never when another agent passes it along. (A child lead may take the non-production approvals its charter hands it, in its own session.)

The top lead starts members and briefs each one in a file. Task workers, such as builders, verifiers and critics, do one job and report once. Permanent members run for days: a watcher reads its sources on a timer, and a tracker keeper wakes when a pull request it follows changes. A stream too complicated for one worker gets a child lead with its own workers. That is the last level: a child lead never starts another lead, and workers start no members, apart from short-lived helpers a skill needs.

Every member reads `RULES.md` first: the standing rules and which actions are gated. `LEAD.md` is the lead's anchor (roster, streams, decisions, open questions), so a lead that loses its context can pick up again.

Reports travel three ways, each tested before anything depends on it: members report to the lead that started them, the lead pushes a notification to you for anything you must see, and, if you set one up, the top lead pages you for critical, time-bound harm you haven't answered.

## How a run goes

1. **Setup.** The lead writes `RULES.md` and `LEAD.md` from templates, asks its questions in one batch, sends a test push for you to confirm, starts any permanent members, and replies with the roster and what waits on you.
2. **The lead's loop.** Each time it wakes, on a message or a wake-up, the lead reads what members sent, spot-checks the claims that matter, records decisions in `LEAD.md`, archives finished members and checks that permanent members are alive. It replies only when you need to know or decide something: no progress ticks.
3. **Approvals.** Production changes, merges, marking pull requests ready, DNS and drafts under your name are gated by default. Each takes two yeses: one after the lead shows you the exact command, target, effect and undo, and one right before it runs. Members never hold an approval; they stop and tell the lead.
4. **Carrying work to done.** When you ask for an outcome such as "ship it", the lead fixes review findings, failing checks and conflicts itself, and stops only at a real gate.
5. **Cleanup.** Whoever starts a member archives it once its final answer is read, the lead sweeps the fleet at each phase's end, and a lead keeps about eight members live at a time.

## Getting started

### On bb

1. Install the skill (below).
2. Start a new thread and ask for a lead, for example: "Use the dispatch skill to lead a fleet that migrates our CI to the new runners. I'm in America/Toronto and away overnight."
3. Answer the lead's setup questions, confirm the test push reached your devices, and say whether an emergency page exists.
4. From then on, talk to that thread. Members are its child threads, and the thread's storage holds the fleet files.

bb supplies the parts a fleet needs: child threads, wake-ups, push notifications and a checklist. `SKILL.md` maps each one.

### On a bare harness: pi, Claude Code or Codex

Here `scripts/fleet.py` does bb's job: it keeps the fleet in a folder, runs each member as a headless session (a harness started by a script, with no terminal of its own) through a small broker process outside any sandbox, delivers messages and runs wake-ups. It needs Python 3.9 or later. Below, `SKILL` and `FLEET` are the absolute paths of the skill and the fleet's folder, and `fleet.py` is short for `python3 "$SKILL/scripts/fleet.py" --fleet "$FLEET"`.

1. Choose a headless lead for work that carries on while you are away, or an interactive lead that acts only while you keep its session open.
2. Write `$FLEET/fleet.json` from the worked example in [`references/bare-harness.md`](references/bare-harness.md): the flags members run with, where worktrees may live, which read-only checks wake-ups may run, and how to notify you.
3. Write the lead's startup prompt to `$FLEET/lead-prompt.md`: the goal, the gates in your own words, and how you will reach it ([`references/fleet-files.md`](references/fleet-files.md) has a template). Then, from a normal terminal (not inside a harness sandbox), in the folder the lead will work in, start the fleet:

   ```bash
   python3 "$SKILL/scripts/fleet.py" --fleet "$FLEET" init --lead lead --harness codex --prompt-file "$FLEET/lead-prompt.md"
   ```

   For an interactive lead, skip the prompt file, run `init --lead lead` instead and open your harness in the same folder.
4. Steer a headless lead with `fleet.py tell lead "..."`, read its latest reply in `$FLEET/agents/lead/final.md`, and see the roster with `fleet.py status`. Give approvals only in the lead's own session: for a headless lead, attach to it with `fleet.py attach lead`.

[`references/bare-harness.md`](references/bare-harness.md) has each harness's flags, models and limits.

## Install

```bash
git clone https://github.com/kalindudc/shell.git
cp -R shell/home/.agents/skills/dispatch ~/.agents/skills/dispatch
```

Dispatch builds on two skills from the same folder: `delegation`, for which model gets which job and how to brief it, and `critique`, for reviews by three critics on three model families. Copy them too, or tell the lead which models and reviews you use instead. If your harness looks for skills somewhere else, copy the folder there or give the lead its path.

## What's in the folder

| File | What it's for |
| --- | --- |
| `GUIDE.md` | This guide, for people. |
| [`SKILL.md`](SKILL.md) | The lead's instructions, written for agents. Only its Guardrails are hard; the rest are defaults to adapt. |
| [`references/fleet-files.md`](references/fleet-files.md) | The fleet's folder, setup, taking over from another lead, and templates for `RULES.md` and `LEAD.md`. |
| [`references/briefs.md`](references/briefs.md) | Starting members, brief templates, steering and critic reviews. |
| [`references/members.md`](references/members.md) | Permanent members: charters, wake-ups, sentinel scripts and liveness. |
| [`references/child-leads.md`](references/child-leads.md) | When to start a child lead, its charter and its limits. |
| [`references/comms.md`](references/comms.md) | Replies, morning packets, trackers and progress numbers. |
| [`references/risk.md`](references/risk.md) | High-risk changes, mitigating first, monitoring that's proven to work, and automatic rollback. |
| [`references/bare-harness.md`](references/bare-harness.md) | Running a fleet on pi, Claude Code or Codex with `fleet.py`. |
| [`references/lessons.md`](references/lessons.md) | What went wrong in the runs this skill came from, and the rule that answers each problem. |
| [`scripts/`](scripts) | `fleet.py`, the bare-harness runtime; `fleet-status.py`, a roster table on bb; `pr-sentinel.py`, a read-only pull request watcher for wake-ups; and their tests. |
| [`tests/livetest/`](tests/livetest) | One repair scenario run under bb, pi, Claude Code and Codex to test the process itself. |

## Where the rules came from

Dispatch distills one lead session that ran an infrastructure migration for three days: about 200 messages from the human and more than 1,000 reports from about 100 helper agents. The skill's first runs refined it further. [`references/lessons.md`](references/lessons.md) pairs each thing that went wrong with the rule that answers it, such as missed updates, a lead whose anchor file went unwritten across seven compactions, and a sub-lead that collected 24 helpers. Read it when a rule seems too strict, or when you explain the process to someone else.
