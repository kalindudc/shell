---
name: plan-generator
description: Generate structured implementation plans for vertical slices of working software with comprehensive research, codebase context, and validation gates
---

# Plan Generator Skill

## Purpose

A plan is a structured prompt that supplies an AI coding agent with everything it needs to deliver a vertical slice of working software -- no more, no less.

A plan differs from a generic project plan by adding three AI-critical layers:

- **Context** -- Precise file paths, library versions, code snippets. Plans are always standalone -- all relevant context is embedded directly.
- **Implementation Strategy** -- Specific libraries, code standards, repo patterns, architectural decisions.
- **Validation Gates** -- Deterministic checks (build, test, lint) with TDD for quality control.

## Research Process

Begin with thorough research to gather all necessary context:

### 1. Documentation Review
- Check `**/docs/` directories for relevant documentation

### 2. Web Research
- Research the concept, library documentation, and sample implementations

### 3. Template Analysis
- Review past plans in `./tmp/plan/` for consistency and inspiration, but, follow our concept, standard and template

### 4. Codebase Exploration
- Identify relevant files, directories, and patterns to follow
- Use the `codebase-explorer` skill for systematic research if the repo is unfamiliar

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

## Rules and requirements
- ALWAYS update the source plan after each task and keep our source-of-truth up-to-date
- MAINTAINABILITY above all else
- ALWAYS follow KISS (keep it simple stupid), AVOID over engineering
- ALWAYS use `dev` or `task` (go-task) commands over manual commands, if needed, prompt the user for clarification on building new commands
```

## Plan Size Guidance

A plan should be implementable in a single session. If it can't be, split it into a plan stack -- multiple independent plans in a directory, each self-contained.

Keep plans concise:
- Implementation Notes: focus on what the agent can't infer from the code
- Low-Level Tasks: enough detail to implement unambiguously, not more
- Context sections: file paths and brief descriptions, not full file contents

**CRITICAL:** Plan stacks are a last resort. Always prefer a single plan, if a stack is a needed, STOP, and confirm with the user before proceeding.

## Output Format

- Output as markdown to `./tmp/plan/<feature_name>-plan.md`
- After creation, inform the user of where to find the plan and provide a brief summary

## User Interaction

After completing initial research, present findings to the user and confirm:

- The scope of the plan
- Patterns to follow and existing features to mirror
- Implementation approach, dependencies, and libraries
- Validation criteria

If the user answers with "continue", proceed with plan creation without additional user input.

## Rules

- ONLY generate the plan document and DO NOT implement any code changes
- DO NOT generate any other documents like PR descriptions
- NEVER create multiple plans for the same feature / task
- ALWAYS use a single plan as the source of truth
- MAINTAINABILITY above all else
- ALWAYS follow KISS (keep it simple stupid), AVOID over engineering
