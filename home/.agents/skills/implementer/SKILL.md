---
name: implementer
description: Execute an explicitly supplied implementation-plan file with verification and bounded retry. Ordinary coding requests do not require a plan workflow; use cortex-implementer for Cortex task IDs.
---

# Implementer Skill

## Purpose

Execute the plan file the user explicitly supplied, with evidence-based verification and bounded recovery. Do not create a plan or require a planning workflow for an ordinary coding request. Cortex task execution belongs to `cortex-implementer`; this file-based workflow owns only its supplied plan file and authorized implementation.

## Plan Ingestion

A plan file MUST be explicitly provided by the user. Do NOT auto-discover or assume a plan.

1. If `$ARGUMENTS` contains a file path, use that. Otherwise, ask the user.
2. Read the plan file completely.
3. Extract tasks from "Low-Level Tasks" if present; for non-standard formats (analysis reports, recommendation docs), explicitly list inferred tasks and re-order by structural dependency when targeting the same file. If ambiguous, ask the user.
4. For each task, identify: target files, functions, implementation details, verification commands.
5. Classify status: Completed (`[COMPLETED]`), In progress (`[IN PROGRESS]`), or Pending (no marker).
6. Enumerate all tasks and their statuses. Track progress by updating task markers in the plan file.
7. Identify the beginning-context sources and required task evidence. Reuse applicable current contents; load missing/changed context in setup or the relevant task, not once at every stage.
8. Use the plan as a guide, not a strict contract, deviations can be made to achieve the overall goal but must be documented and approved by the user

### Resuming Partially Completed Plans

If any tasks are marked completed or in progress, this is a resume:

- Verify completion records against applicable current source/validation evidence; read missing or changed targets, and re-mark as pending when the claimed changes are absent.
- Resume in-progress work without restarting completed, still-valid work.
- Use the single baseline decision in Pre-Implementation Setup; do not run a second resume-only build/test cycle.
- Report material resume state and blockers, not a repeated inventory that has not changed.

## Pre-Implementation Setup

1. Branch check: Verify you are NOT on `main`. If on `main`, propose a branch name without prompting for confirmation. If the GitHub stack extension is available (`command -v gh >/dev/null 2>&1 && gh stack --version >/dev/null 2>&1`), preconfigure `git config rerere.enabled true` to avoid an interactive prompt, then create the bottom stack layer with `gh stack init --base main <branch_name>`. Otherwise, create the branch with `git checkout -b <branch_name>`. ALWAYS pass the branch name to `gh stack init`; never invoke its interactive form.
2. Baseline: Select checks that actually cover the planned change, inspecting their scope/side effects. Reuse an existing baseline only while revision, environment, coverage, and freshness apply. Run missing relevant checks once. If NOT green, STOP and report the exact failures; continue only after explicit baseline acceptance and record that failure set as the regression contract. Documentation-only work uses applicable source/config checks; executable CREATE work is not exempt from runtime verification.
3. Context: Verify required existing paths and expected-new targets, then load only missing/changed relevant context. Preserve unrelated user changes; a dirty worktree is not permission to clean it.

BRANCH NAME TEMPLATE: `<github-username>/<feat|fix|chore>_<short-description>`

## Execution Loop

For each Low-Level Task, in order:

### Step 1: Parse

- Read the task description from the plan
- Identify: target files, functions to create/update, specific details
- Track progress by marking the task as `[IN PROGRESS]` in the plan file

### Step 2: Context

- Establish the relevant current definitions, callers, and contracts before editing; reuse complete applicable context rather than rereading it by rote.
- For CREATE, verify the target is absent and the intended root/nearest existing parent is correct; create planned directories only within that scope.
- For UPDATE, load missing/changed content and expand to the full file when needed to understand dependencies or safe edit boundaries.
- Refresh after relevant changes, truncation/context loss, or a material freshness gap; never replace uncertainty with an invented current state.

### Step 3: Implement

Make the authorized changes using the Agent Protocol's risk-scoped communication: a concise intention and verification result for ordinary changes, and the full action cycle when its risk/request conditions warrant it.

Guidelines:
- Prefer the Edit tool over Write for existing files
- Prefer editing existing files over creating new ones
- Follow the project's coding standards (from the plan's Implementation Notes)
- Follow the plan's specific instructions for each task
- When multiple tasks target the same file, treat the plan as a specification and batch implementation -- the plan's value is in completeness, not edit granularity
- Use the registered edit tool's exact, non-overlapping replacements; batch disjoint edits per file. Do not assume a replaceAll parameter exists.
- Pre-check linter configs for strict rules before writing code to avoid create-then-rewrite cycles. When consolidating modules, expect length-limit violations. When changing data formats, update test helpers that bypass the app layer.
- Do NOT deviate from the plan without user approval -- surface simpler alternatives before committing
- When a plan conflicts with tooling/environment conventions, research the convention before overriding it

### Step 4: Verify

Run the verification command appropriate for the change type:

Scope: Run relevant checks after a coherent change invalidates their evidence. Reuse still-applicable results; add broader coverage once when the integrated change requires it, not automatically after every task.

- Code changes: Run targeted behavior tests and compilation/type checks when relevant. A command named build is not evidence if it builds an unrelated artifact.
- New tests: Demonstrate the intended RED before implementation, then GREEN after it. Expected test-first failures are not an accepted production baseline or a reason to claim success.
- Style changes: Use applicable non-modifying checks; an auto-fixer is another authorized edit, not a read-only test.
- Structural changes: Verify intended paths and references.
- Config/doc-only plans: Use relevant structural/config validators and source review, not an unrelated build/test/lint cycle. Inspect Git state to protect unrelated user changes rather than demanding cleanup.
- CREATE-only executable code: Run relevant runtime/behavior verification just as for changed executable code. File existence or a clean Git status does not prove behavior.
- Unavailable runtime: When a plan specifies runtime verification for a runtime not available locally, explicitly flag the deviation in the task record and recommend manual verification rather than silently skipping. This is distinct from missing credentials (which allow structural validation) -- missing runtimes block functional verification entirely.
- Compilation-dependency chains (A references B, B removes C): Defer verification to the last task in the chain rather than attempting intermediate builds that cannot succeed.

Use `test_run_parsed` when its registered contract fits the command; otherwise use the verified project command directly. Check the actual exit status and parsing limits. Unparsed/Minitest results require reading the raw evidence; null counts or an empty parsed-failure list never establish that tests passed.

When test failures produce stack traces, use `stack_trace_resolve` to resolve compiled/container paths to actual source file:line references in the workspace.

Use `ast_query` to find patterns to follow when implementing (e.g., "find all classes extending BaseModel" to match existing conventions). Prefer over grep for structural code queries.

Compare RESULT vs EXPECT:
- If verification passes: proceed to Step 5
- If verification fails: enter the Retry Protocol (see below)

### Step 5: Record

- Update the plan file in-place: mark the task as `[COMPLETED]` in the plan file
- If there were any deviations from the plan, add a note below the task:
  ```
  > Deviation: [what changed and why]
  ```
- If the user requests a deviation, update the plan inline with the deviation marker and continue -- user-initiated changes are pre-approved.

### Step 6: Checkpoint at a meaningful milestone or changed scope

- Re-anchor to the objective already in context; reread the plan only if its evidence was lost or changed.
- Verify current implementation still aligns with the user's goal; a task counter alone does not require another read/check.
- If drift detected: STOP, report to user, wait for confirmation before continuing
- If a task reveals the plan's approach is fundamentally flawed (not just the task implementation), STOP and present your finding. The plan may need revision before continuing -- do not force a broken plan to completion.

## Retry Protocol

When verification fails at Step 4:

Up to 3 retries. Each attempt: read the error, state the exact failure, state your root-cause theory, adjust the implementation, re-run verification.

If all 3 attempts fail:
- STOP -- do not continue to the next task
- Report to user:
  1. What failed (exact error)
  2. What was attempted (all 3 approaches)
  3. Theory of root cause
  4. Proposed next step
- Wait for user confirmation before continuing

Critical: NEVER silently retry -- state what changed and why. NEVER modify tests blindly -- verify they're correct first. NEVER modify the plan to fit broken code.

## Completion Protocol

After all tasks are completed:

1. Account for every planned validation gate using current evidence and identify any remaining unverified scope.
2. Run the applicable remaining validation gates once; reuse still-valid results and do not add an unrelated build/lint cycle. Compare any new failures with the explicitly accepted baseline regression contract; report unchanged accepted failures as pre-existing, not green.
3. Report final status: tasks completed (N/N), validation gates (pass/fail), files touched, deviations. Use the `git_diff_summary` tool for the final changeset summary -- it provides structured file categorization and counts instead of raw diff output. Supplement with `git status` when the plan creates new files, since `git_diff_summary` only covers tracked changes and will miss untracked files.
4. Update the plan with `## Implementation Status: COMPLETED` at the top

## Self-Improvement

Capture feedback only for concrete, novel, reusable evidence from this task and within its authorized scope. Ordinary success or restating existing guidance starts no notes read, observer, or promotion.

When capture is justified, the current agent owns the gate: resolve `SKIP_SKILL_NOTES` from the environment only (never `.env`); `1` or `true` disables notes. Otherwise use the `improve-skills` Fast Loop. Reuse applicable evidence; one owner and at most one entry per skill/session. A delegated observer receives `notes_enabled=true`, the target, and the concrete observation.

## Rules

- ALWAYS track the core protocol with TODOs or Quests, if the tooling supports it
- NEVER skip a task -- execute them in strict order
- NEVER modify the plan's High-Level or Mid-Level Objectives
- NEVER work on `main` branch -- always use feature branches
- NEVER deviate from the plan without user approval
- Follow TDD: verify tests are correct before relying on them. Update tests only with clear justification.
- MAINTAINABILITY above all else. Follow KISS.
- When confused: stop, present theories, get user signoff. Uncertainty expressed > uncertainty hidden.
