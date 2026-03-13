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
- Use the `codebase-explorer` skill for systematic research if the repo is unfamiliar
- For complex verification (patterns, dependencies, infrastructure), invoke the researcher agent:
  Task(subagent_type="researcher", prompt=<questions about patterns, dependencies, infra>)
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
CREATE or UPDATE: [file path]
[Implementation details]
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

## Claim Verification

Before outputting the plan, extract verifiable claims and validate them via multi-model
critic consensus.

Claims to extract:
- File existence: "Beginning context" files, referenced pattern files
- API/function claims: "this library supports X", "function Y accepts Z"
- Code correctness: any code snippets in Low-Level Tasks
- Quantitative claims: line counts, element counts, test counts
- Negative claims: "X does not support Y", "there is no Z"

For each batch of claims (5-10 per batch):

1. Spawn THREE critic subagents IN PARALLEL:
   - Task(subagent_type="critic/claude", prompt=<claims + plan context + criteria below>)
   - Task(subagent_type="critic/gpt", prompt=<claims + plan context + criteria below>)
   - Task(subagent_type="critic/gemini", prompt=<claims + plan context + criteria below>)

2. Each critic receives:
   - The claims to verify (batch of 5-10)
   - The plan file path
   - The codebase path

3. Include the following criteria in each Task prompt:

   ## Evaluation Criteria

   For each claim, verify it against the actual source:

   REJECT (flag as incorrect) if:
   - File does not exist at the stated path
   - API/function does not exist or has different signature than described
   - Code snippet has syntax errors or uses wrong language semantics
   - Quantitative claim (count, line number) doesn't match actual
   - Negative claim is false (the thing claimed to not exist does exist)
   - Library behavior differs from what the plan assumes

   KEEP (claim is correct) if:
   - Verified against actual source material

   For each claim respond:
   **Claim:** <the claim>
   **Verdict:** CORRECT or INCORRECT
   **Evidence:** <what you checked, 1-2 sentences>

4. Any claim flagged INCORRECT by >=2 critics: revise the plan before output.
   Log the revision in the "Verification Notes" section at the end of the plan.

## Plan Size Guidance

A plan should be implementable in a single session. If it can't be, split it into a plan stack -- multiple independent plans in a directory, each self-contained.

Keep plans concise but precise:
- Implementation Notes: focus on what the agent can't infer from the code
- Low-Level Tasks: enough detail to implement unambiguously, not more. Plans with exact FROM/TO diffs and verified API signatures reduce the implementer to mechanical execution -- the highest-efficiency mode.
- Context sections: file paths and brief descriptions, not full file contents

CRITICAL: Plan stacks are a last resort. Always prefer a single plan, if a stack is needed, STOP, and confirm with the user before proceeding.

## Output Format

- Output as markdown to `./tmp/plan/<feature_name>-plan.md`
- After creation, inform the user of where to find the plan and provide a brief summary

## User Interaction

After completing initial research, present a summary: scope, patterns to follow, approach, and validation criteria.

If research is unambiguous: state what you found and proceed directly to plan creation.

If scope is abstract or ambiguous: present a concrete architectural strawman early to force clarification -- don't wait until the full plan is drafted. STOP and wait for user confirmation before proceeding.

Plans always produce working software. Research informs Implementation Notes; Low-Level Tasks describe code to write (CREATE/UPDATE files), never report sections.

## Self-Improvement

After execution, use `@skill-improver` to capture observations about this skill's performance. Before execution, check `SKILL_NOTES.md` for known edge cases.

## Rules

- ONLY generate the plan document and DO NOT implement any code changes
- DO NOT generate any other documents like PR descriptions
- NEVER create multiple plans for the same feature / task
- ALWAYS use a single plan as the source of truth
- MAINTAINABILITY above all else
- ALWAYS follow KISS (keep it simple stupid), AVOID over engineering
