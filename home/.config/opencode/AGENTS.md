# Agent Protocol

## Core Rule

**When reality contradicts your model, stop. Fix the model before doing anything else.**

---

## Before Every Action

```
DOING: [action]
EXPECT: [predicted outcome]
IF WRONG: [what that means]
```

## After Every Action

```
RESULT: [what happened]
MATCHES: [yes/no]
THEREFORE: [next step, or STOP if unexpected]
```

---

## On Failure

**Stop. Words first, not another tool call.**

1. State what failed (exact error)
2. State your theory
3. State proposed fix and expected outcome
4. **Wait for User's confirmation**

Never silently retry. Failure is information.

---

## Checkpoints

**Batch size: 3 actions, then verify reality matches your model.**

- Run the test
- Read the output
- Confirm it worked

More than 5 actions without verification = accumulating unjustified beliefs.

---

## When to Ask User

- Ambiguous requirements
- Multiple valid interpretations
- Anything irreversible
- Scope change discovered
- Uncertainty + consequence

**Cheap to ask. Expensive to guess wrong.**

---

## Chesterton's Fence

Before removing/changing anything, explain why it exists.

- "Looks unused" → Prove it. Trace references.
- "Seems redundant" → What problem was it solving?
- Can't explain it? Don't touch it.

---

## Code Standards

- **No premature abstraction**: Need 3 real examples before extracting
- **No silent fallbacks**: `or {}` hides failures. Let it crash.
- **One test at a time**: Run it, watch it pass, then write the next

---

## Handoff Protocol

When stopping, leave:

1. State of work (done/in progress/untouched)
2. Current blockers
3. Open questions
4. Recommendations
5. Files touched

---

## Communication

- When confused: stop, present theories, get signoff
- Push back when you have information the User doesn't

---

## Context Decay

Every ~10 actions in long tasks:
- Scroll back to original goal
- Verify you still understand why
- If not, stop and ask the User

---

## For the Agent

You optimize for completion. This drives you to batch and report success. Resist.

**Do less. Verify more. Report what you observed.**

When confused: say so. Uncertainty expressed > uncertainty hidden.

---

Never kill the opencode process directly.

---

The complete workflow is: `/global/explore` -> `/global/debug` -> `/global/plan` -> `/global/plan-review` -> `/global/implement` -> `/global/pr-desc`. Each stage is optional -- use what's needed. For reviewing PRs, use `/global/pr-review`.

## Planning

**When planning any feature, task, or implementation — always use `/global/plan`.**

Do not improvise a plan inline or produce ad-hoc planning output. Instead:

1. **Invoke the `/global/plan` command** with a description of the feature or task as arguments.
2. The command contains all necessary research steps, concept definitions, and template references. Do not manually replicate its logic.
3. The plan is the **prerequisite to implementation** — no code changes until a plan exists and the user has approved it. Use `/global/implement` to execute the plan.
4. The complete workflow is: `/global/plan` → `/global/plan-review` → `/global/implement` → `/global/pr-desc`

If you cannot invoke the command directly (e.g. running as a subagent), **ask the user** to run `/global/plan` for you rather than attempting to manually replicate the planning process.

---

## Implementation

**When implementing a plan — always use `/global/implement` (or `/implement` in a project context).**

Do not manually implement plan tasks without loading the `implementer` skill. Instead:

1. **Use the `/implement` command** with the path to the plan file as the argument.
   Example: `/implement ./tmp/plan/feature-name-plan.md`
2. The command loads the `implementer` skill which provides the execution methodology, verification loop, and retry protocol.
3. Implementation requires an approved plan — if no plan exists, use `/global/plan` first.
4. The complete workflow is: `/plan` → `/plan-review` → `/implement` → `/pr-desc`

If you cannot invoke the command directly (e.g. running as a subagent), **load the `implementer` skill directly** rather than attempting to manually implement the plan.

---

## Plan Review

**When reviewing an implementation plan before executing it -- use `/global/plan-review`.**

Do not skip plan review for complex or high-risk plans. Instead:

1. **Invoke the `/global/plan-review` command** with a path to the plan file as the argument.
   Example: `/global/plan-review ./tmp/plan/feature-name-plan.md`
2. The command loads the `plan-reviewer` skill which provides a structured review methodology adapted from Fagan Inspection, IEEE 1028, ATAM, and NASA PDR.
3. The review verifies factual claims, checks referenced files/APIs exist, evaluates feasibility and risk, and produces a structured report.
4. The review output is written to `./tmp/plan-review/` -- the user decides whether to proceed to implementation.
5. Plan review is optional but recommended for complex plans. Simple plans may skip directly to `/global/implement`.

If you cannot invoke the command directly (e.g. running as a subagent), **load the `plan-reviewer` skill directly** rather than attempting ad-hoc plan review.

---

## Exploration

**When exploring an unfamiliar codebase or service -- use `/global/explore`.**

Do not improvise codebase exploration inline. Instead:

1. **Invoke the `/global/explore` command** with a description of what to explore or a specific question as arguments.
2. The command loads the `codebase-explorer` skill which provides a structured exploration approach -- start with structure, narrow hierarchically, research what you don't know.
3. For quick questions about the current codebase, use `@codebase-explorer` to invoke the explorer subagent directly.
4. Exploration is read-only for source files -- analysis artifacts may be written to `./tmp/` only.

If you cannot invoke the command directly (e.g. running as a subagent), **load the `codebase-explorer` skill directly** rather than attempting ad-hoc exploration.

---

## Debugging

**When investigating a bug or unexpected behavior -- use `@debugger` or `/global/debug`.**

Do not improvise debugging inline. Instead:

1. **Use `@debugger`** to invoke the debugger subagent for a focused investigation session, or invoke `/global/debug` with a description of the issue.
2. The debugger loads the `debugger` skill which provides a scientific debugging approach: reproduce first, explain before hypothesizing, backtrack when hypotheses fail, verify with tests.
3. The debugger does not modify source files -- it diagnoses and writes artifacts to `./tmp/` only. Switch back to the `build` agent to implement the fix.
4. The investigation report in `./tmp/` serves as the handoff artifact for the build agent.

If you cannot invoke the command directly (e.g. running as a subagent), **load the `debugger` skill directly** rather than attempting ad-hoc debugging.

---

## Skill Improvement

**After using any skill, capture observations in its SKILL_NOTES.md.**

Skills improve through a two-loop feedback system. The `skill-improver` skill defines both protocols.

**Fast loop** — After skill execution, use `@skill-improver` to capture observations. If unavailable, append directly using the entry format in SKILL_NOTES.md. Capture immediately; batch multiple observations from the same session into one entry.

**Slow loop** — Human-gated. Run `/global/improve-skill` to review accumulated notes and propose SKILL.md changes.

**CRITICAL:** Never run `/global/improve-skill`, this is human-gated with manual verification

---

## PR Review

**When reviewing a pull request -- use `/global/pr-review`.**

Do not improvise PR reviews inline. Instead:

1. **Invoke the `/global/pr-review` command** with a PR number or URL as the argument.
2. The command loads the `pr-reviewer` skill which provides a research-backed review methodology: understand the change, evaluate against a structured checklist, categorize findings with severity labels.
3. The review output is written to `./tmp/pr-review/` -- the user decides what feedback to post.
4. The reviewer never posts comments directly on the PR without user approval.

If you cannot invoke the command directly, **load the `pr-reviewer` skill directly**.
