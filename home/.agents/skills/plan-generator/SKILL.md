---
name: plan-generator
description: Generate structured implementation plans for vertical slices of working software with comprehensive research, codebase context, and validation gates
---

# Plan Generator Skill

## Purpose

A plan is a structured prompt that supplies an AI coding agent with everything it needs to deliver a vertical slice of working software -- no more, no less.

A plan differs from a generic project plan by adding three AI-critical layers:

- Context -- Precise file paths, library versions, code snippets. Plans are always standalone -- all relevant context is embedded directly.
- Implementation Strategy -- Specific libraries, code standards, repo patterns, architectural decisions.
- Validation Gates -- Deterministic checks (build, test, lint) with TDD for quality control.

---

## Core protocol

RESEARCH PHASE: Complete all investigation before writing.
DECISION POINT: Write one sentence: "Approach: [what will be implemented]"

Draft → Verify → Fix → Repeat (max 3 rounds)

Cheap checks:
- Task count ≤10
- Task block ≤25 lines
- Tasks numbered, not ### headers
- Implementation Notes: flat bullets
- FROM blocks: changed lines only
- CREATE blocks: signatures only
- Context: only files plan modifies

If ANY fail: fix and re-verify.

WRITE PHASE: Once research AND verification complete, re-read the Plan Template, Plan Size Guidance, and Pre-Write Checklist sections of this skill file before writing. Then use the template. Reference decisions from exploration, not assumptions or alternatives.

---

## Research Process

Begin with thorough research to gather all necessary context:

### 1. Documentation Review
- Check `**/docs/` directories for relevant documentation

### 2. Web Research
- Research the concept, library documentation, and sample implementations
- Research platform/framework extension points and API constraints before drafting architecture -- feasibility shapes design
- Prefer named formal standards and peer-reviewed methodologies over generic "best practices" articles

### 3. Template Analysis
- Review past plans in `./tmp/plan/` for consistency and inspiration, but, follow our concept, standard and template

### 4. Codebase Exploration
- Identify relevant files, directories, and patterns to follow
- Read full content of ALL pattern files (not just the closest analog) -- consistency comes from breadth
- Verify both what patterns exist AND what infrastructure is absent -- missing frameworks/conventions are as important as existing ones
- Before proposing edits to config or deployed files, check if they are produced by a build/template system (Makefile, Taskfile, ERB, Jinja, code generation). Search for generator scripts, `src/templates/`, and build task definitions -- editing generated files directly will be overwritten
- Use the `codebase-explorer` skill for systematic research if the repo is unfamiliar
- For complex verification (patterns, dependencies, infrastructure), invoke the researcher agent.
  In Pi, use the subagent tool with the `researcher` agent. In OpenCode, use `Task(subagent_type="researcher", ...)`.
  The researcher returns verified findings with confidence levels and file:line evidence,
  replacing ad-hoc Read/Glob calls for complex verification. Simple file reads remain inline.
  If the researcher fails or times out, fall back to inline verification.

### Available Custom Tools

Use these tools during the research process to gather context efficiently:
- `ast_query` -- structural AST pattern search. Use to find code patterns to follow (e.g., "find all classes extending BaseModel", "find all route handlers"). Prefer over grep for structural queries.
- `git_blame_context` -- structured blame info (who, when, why, co-changed files). Use to understand why existing code exists before planning changes around it.
- `git_diff_summary` -- structured diff summary with file categorization and counts. Use to understand recent changes to relevant modules.
- `test_run_parsed` -- run tests with structured pass/fail results. Use to verify the baseline test suite passes before planning.
- `stack_trace_resolve` -- resolve stack traces to actual source file:line references.
- `gh` CLI / GitHub API -- use `gh api` and `gh search` for repo configuration state (branch protection, secrets, app installations). Verify commands work before including them in plans.

---

## Plan Template

Use the following structure for every plan:

```markdown
# Plan: <title>

> Ingest the information from this file, implement the Low-Level Tasks, and generate the code that will satisfy the High and Mid-Level Objectives.

## High-Level Objective

- [Goal]

## Mid-Level Objective

- [Measurable steps toward the goal]

## Implementation Notes

- [Technical details, dependencies, coding standards]

## Context

### Beginning context

- [Files that exist at start]

### Ending context

- [Files that will exist at end]

## Low-Level Tasks

> Ordered from start to finish

1. [Task description]

\```
UPDATE: [file path]
FROM:
  [exact lines being replaced]
TO:
  [exact replacement lines]
\```

\```
CREATE: [file path]
[Exported signatures with exact types]
[Key algorithmic decisions the implementer cannot infer from context]
[What to import and from where]
DO NOT write the implementation -- that is the implementer's job.
\```

## Validation Gates

- [Completion criteria]

## Verification Notes
[Claims verified by multi-model consensus. Revisions made: ...]
[If no revisions needed: "All claims verified."]

## Rules and requirements
- ALWAYS update the source plan after each task and keep our source-of-truth up-to-date
- MAINTAINABILITY above all else
- ALWAYS follow KISS (keep it simple stupid), AVOID over engineering
- ALWAYS use `dev` or `task` (go-task) commands over manual commands, if needed, prompt the user for clarification on building new commands
```

---

## Claim Verification

Before outputting the plan, extract verifiable claims and validate them.

Claims to extract:
- File existence: "Beginning context" files, referenced pattern files
- API/function claims: "this library supports X", "function Y accepts Z"
- Code correctness: any code snippets in Low-Level Tasks
- Quantitative claims: line counts, element counts, test counts
- Negative claims: "X does not support Y", "there is no Z"

Invoke multi-model consensus to verify claims. If consensus tooling is unavailable, perform inline verification and note the limitation in Verification Notes.

In Pi, use the subagent tool with a consensus agent when available. In OpenCode, use `Task(subagent_type="consensus", ...)`.

When performing inline verification (consensus unavailable):
- For each file existence claim, verify with `ls` or `find`
- For each API/function claim, verify by reading the source
- For each code snippet, verify syntax and semantics
- Log results in "Verification Notes"

Any claim flagged INCORRECT: revise the plan before output. Log the revision in the "Verification Notes" section at the end of the plan.

---

## Plan Size Guidance

A plan should be implementable in a single session. If it can't be, split it into a plan stack -- multiple independent plans in a directory, each self-contained.

Keep plans concise but precise:
- Implementation Notes: focus on what the agent can't infer from the code
- Low-Level Tasks: enough detail to implement unambiguously, not more. Plans with exact FROM/TO diffs and verified API signatures reduce the implementer to mechanical execution -- the highest-efficiency mode.
- Context sections: file paths and brief descriptions, not full file contents

Task block rules:
- UPDATE tasks contain ONLY the changed lines as FROM/TO diffs -- never the whole file
- CREATE tasks contain ONLY exported signatures, key decisions, and imports -- never a full implementation
- A task block over 25 lines is a red flag: review it and strip anything the implementer can infer
- "Standalone" means all context needed to make a decision is present, NOT that the plan contains the code
- When deduplicating shared mechanics across 3+ skills (60+ lines of near-identical code), extract to a hidden orchestrator agent (agent = execution, skill = methodology). Quantify the overlap first to validate the extraction.

Anti-patterns -- NEVER do these:
- Implementation Notes with ### subsections, tables, or multi-level nesting. Implementation Notes are a FLAT bullet list. Each bullet is a decisive technical fact the implementer cannot infer from code.
- Low-Level Tasks that produce no files. Every task MUST be a CREATE or UPDATE on a specific file. Research and verification are NOT tasks -- they belong in Implementation Notes or Validation Gates.
- Beginning context listing files the plan does not touch. List ONLY files the plan creates, updates, or reads as direct input for those changes.
- Mid-Level Objectives that echo the Low-Level Task list. Mid-Level Objectives are measurable outcomes, not a file-by-file inventory.
- Validation Gates asserting per-section content for every file. Use focused automated checks.

CRITICAL: Plan stacks are a last resort. Always prefer a single plan, if a stack is needed, STOP, and confirm with the user before proceeding.

### Constraint Enforcement

HARD LIMITS:
- Max 10 - 15 tasks
- Max 25 - 35 lines per task block
- Max 300 - 650 lines total

If exceeded: prefer consolidation first. If still over limits, create plan stack per existing protocol (STOP, confirm with user, split into multiple independent plans).

---

## Pre-Write Checklist

STOP. Before writing the plan, complete every item. Do NOT skip this.

1. Re-read the Plan Template and Plan Size Guidance sections of this skill file (use the read tool -- do not rely on memory)
2. Read at least one past plan from `./tmp/plan/` and compare its structure against the template -- match its level of detail, not exceed it
3. Verify:
   - [ ] Approach decided (not "will try X or Y")
   - [ ] All APIs verified (list files: ___)
   - [ ] Implementation notes are decisive technical facts, not explanatory essays
   - [ ] Every planned Low-Level Task is a CREATE or UPDATE operation
   - [ ] Constraint enforcement completed

## Post-Write Review

Before saving the plan file, scan every task block:
- [ ] No UPDATE task contains a full file -- only changed lines
- [ ] No CREATE task contains a full implementation -- only signatures, decisions, low level implementation details for ambiguous code
- [ ] No task block exceeds 25 lines -- if it does, split it into multiple tasks or move details to Implementation Notes
- [ ] No test task contains full test function bodies -- describe what to assert, not how to write it

---

## Output Format

- Output as markdown to `./tmp/plan/<feature_name>-plan.md`
- After creation, inform the user of where to find the plan and provide a brief summary

## User Interaction

After completing initial research, present a summary: scope, patterns to follow, approach, and validation criteria.

If research is unambiguous: state what you found and proceed directly to plan creation.

If scope is abstract or ambiguous: present a concrete architectural strawman early to force clarification -- don't wait until the full plan is drafted. STOP and wait for user confirmation before proceeding.

Plans always produce working software. Research informs Implementation Notes; Low-Level Tasks describe code to write (CREATE/UPDATE files), never report sections.

## Rules

- ALWAYS track the core protocol with TODOs or Quests, if the tooling supports it
- ONLY generate the plan document and DO NOT implement any code changes
- DO NOT generate any other documents like PR descriptions
- NEVER create multiple plans for the same feature / task
- ALWAYS use a single plan as the source of truth
- MAINTAINABILITY above all else
- ALWAYS follow KISS (keep it simple stupid), AVOID over engineering
