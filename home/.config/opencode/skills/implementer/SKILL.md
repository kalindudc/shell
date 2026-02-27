---
name: implementer
description: Execute implementation plans by systematically completing each task with verification, bounded retry, and progress tracking
---

# Implementer Skill

## Purpose

This skill fills the workflow gap between plan creation (`/global/plan`) and PR generation (`/global/generate-pr-description`). It takes a plan file produced by the `plan-generator` skill and executes every Low-Level Task systematically — producing working code on the first pass.

The complete workflow is:

```
/global/plan → /global/implement → /global/generate-pr-description
```

## Plan Ingestion

A plan file **must** be explicitly provided by the user. Do NOT auto-discover or assume a plan.

1. If `$ARGUMENTS` contains a file path, use that. Otherwise, **ask the user**.
2. Read the plan file completely.
3. Extract tasks from "Low-Level Tasks" if present, otherwise infer actionable items. If ambiguous, ask the user.
4. For each task, identify: target files, functions, implementation details, verification commands.
5. Classify status: **Completed** (`[COMPLETED]`, `✅`), **In progress** (`[IN PROGRESS]`), or **Pending** (no marker).
6. Use the **TodoWrite tool** to create a todo for each task with the correct status.
7. Read all files in the "Beginning context" section (or infer from task descriptions).

### Resuming Partially Completed Plans

If any tasks are marked completed or in progress, this is a **resume**:

- **Verify completed tasks** -- read target files and confirm changes exist. Re-mark as `pending` if missing.
- **Resume in-progress tasks** -- continue from where they left off, don't restart.
- **Run a baseline check** -- build and test to confirm a working state. Report failures before continuing.
- **Report resume status** to the user: tasks verified, tasks to resume, tasks remaining.

## Pre-Implementation Setup

1. **Branch check**: Verify you are NOT on `main`. If on `main`, propose a branch name and create it with `gt create` (if available) or `git checkout -b`.
2. **Baseline check**: Run the project's build/test command. If NOT green, STOP and inform the user.
3. **Context loading**: Read all files in "Beginning context". Verify each exists (or note as expected-missing for CREATE tasks).

## Execution Loop

For each Low-Level Task, in order:

### Step 1: Parse

- Read the task description from the plan
- Identify: target files, functions to create/update, specific details
- Mark the corresponding todo as `in_progress`

### Step 2: Context

- Read all files referenced by the task
- If files don't exist yet (CREATE tasks), verify parent directory exists
- If files exist (UPDATE tasks), read current content completely
- Understand the current state before making changes

### Step 3: Implement

Make the code changes described in the task. Follow the DOING/EXPECT pattern from the Agent Protocol.

Guidelines:
- Prefer the **Edit tool** over Write for existing files
- Prefer editing existing files over creating new ones
- Follow the project's coding standards (from the plan's Implementation Notes)
- Follow the plan's specific instructions for each task
- Do NOT deviate from the plan without user approval

### Step 4: Verify

Run the verification command appropriate for the change type:

- **Code changes**: Build command (confirm compilation)
- **New tests**: Test command (confirm tests pass)
- **Style changes**: Lint command (confirm style compliance)
- **Structural changes**: Verify files exist/don't exist as expected

When running tests, prefer the `test_run_parsed` tool over raw bash for structured results. It returns pass/fail per test with parsed failure locations instead of raw terminal output.

Compare RESULT vs EXPECT:
- If verification **passes**: proceed to Step 5
- If verification **fails**: enter the Retry Protocol (see below)

### Step 5: Record

- Update the plan file in-place: mark the task as `[COMPLETED]`
- Mark the corresponding todo as `completed`
- If there were any deviations from the plan, add a note below the task:
  ```
  > Deviation: [what changed and why]
  ```

### Step 6: Checkpoint (every 3 tasks)

- Re-read the plan's High-Level Objective
- Verify current implementation still aligns with the goal
- If drift detected: STOP, report to user, wait for confirmation before continuing
- If a task reveals the plan's approach is fundamentally flawed (not just the task implementation), STOP and present your finding. The plan may need revision before continuing -- do not force a broken plan to completion.

## Retry Protocol

When verification fails at Step 4:

```
attempt = 0
WHILE attempt < 3:
  1. Read the error output carefully
  2. State what failed (exact error message)
  3. State your theory of the root cause
  4. Make an adjustment to the implementation
  5. Re-run verification
  attempt++
```

If all 3 attempts fail:
- **STOP** — do not continue to the next task
- Report to user:
  1. What failed (exact error)
  2. What was attempted (all 3 approaches)
  3. Theory of root cause
  4. Proposed next step
- **Wait for user confirmation** before continuing

Critical: NEVER silently retry -- state what changed and why. NEVER modify tests blindly -- verify they're correct first. NEVER modify the plan to fit broken code.

## Completion Protocol

After all tasks are completed:

1. Run ALL Validation Gates from the plan
2. Run the full build + test + lint cycle
3. Report final status: tasks completed (N/N), validation gates (pass/fail), files touched, deviations. Use the `git_diff_summary` tool for the final changeset summary -- it provides structured file categorization and counts instead of raw diff output.
4. Update the plan with `## Implementation Status: COMPLETED` at the top

## Self-Improvement

This skill improves through use. After execution:
- Append observations to `SKILL_NOTES.md` in this skill's directory
- Note edge cases, successful patterns, and open questions

Before modifications, check `SKILL_NOTES.md` for known edge cases.

## Rules

- NEVER skip a task -- execute them in strict order
- NEVER modify the plan's High-Level or Mid-Level Objectives
- NEVER work on `main` branch -- always use feature branches
- NEVER deviate from the plan without user approval
- Follow TDD: verify tests are correct before relying on them. Update tests only with clear justification.
- MAINTAINABILITY above all else. Follow KISS.
- When confused: stop, present theories, get user signoff. Uncertainty expressed > uncertainty hidden.
