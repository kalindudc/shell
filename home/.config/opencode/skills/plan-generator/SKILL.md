---
name: plan-generator
description: Generate structured implementation plans for vertical slices of working software with comprehensive research, codebase context, and validation gates
---

# Plan Generator Skill

## Purpose

A plan is a structured prompt that supplies an AI coding agent with everything it needs to deliver a vertical slice of working software -- no more, no less.

### How it differs from a generic project plan

A traditional plan over-complicates and over-details to a point where context is misinterpreted, making it difficult for any AI agent to effectively implement. Instead, a plan keeps the goal and justification sections yet adds three AI-critical layers:

**Context** -- Precise file paths and content, library versions and library context, code snippet examples. LLMs generate higher-quality code when given direct, in-prompt references instead of broad descriptions. Usage of a `./tmp/docs/` directory to pipe in library and other docs for this plan.

**Implementation Details and Strategy** -- Explicitly states how a feature will be built. This includes the use of specific libraries, code standards, repo practices / existing patterns, or agent patterns (ReAct, Plan-and-Execute). Usage of typehints, dependencies, architectural patterns and other tools to ensure the code is built correctly.

**Validation Gates** -- Deterministic checks such as `dev test unit` (or equivalent) / `dev test integration` (or equivalent) / `dev style` (or equivalent), with TDD development for quality control will catch defects early and are cheaper than pivoting. Example: Each new addition should be independently tested with unit tests and comprehensively tested with integration tests. Validation gate = all tests pass.

## Research Process

Begin with thorough research to gather all necessary context:

### 1. Documentation Review

- Check for relevant documentation in `**/docs/` directories
- Identify any documentation gaps that need to be addressed

### 2. Web Research

- Use web search to gather additional context
- Research the concept of the feature/product
- Look into library documentation
- Look into sample implementations and examples

### 3. Template Analysis

- Review past plans in the `./tmp/plan/` directory for consistency and inspiration
- Ensure understanding of the template requirements before proceeding

### 4. Codebase Exploration

- Identify relevant files and directories that provide implementation context
- Look for patterns that should be followed in the implementation

### 5. Implementation Requirements

- Confirm implementation details with the user
- Ask about specific patterns or existing features to mirror
- Inquire about external dependencies or libraries to consider

## Plan Template

Use the following structure for every plan:

```markdown
# Plan: <title>

> Ingest the information from this file, implement the Low-Level Tasks, and generate the code that will satisfy the High and Mid-Level Objectives.

## High-Level Objective

- [High level goal -- what do you want to build?]

## Mid-Level Objective

- [Concrete, measurable steps to achieve the high-level objective]
- [Not too detailed -- save details for implementation notes]

## Implementation Notes

- [Important technical details]
- [Dependencies and requirements]
- [Coding standards to follow]
- [Other technical guidance]

## Context

### Beginning context

- [List of files that exist at start]

### Ending context

- [List of files that will exist at end]

## Low-Level Tasks

> Ordered from start to finish

1. [First task]

\```
What prompt would you run to complete this task?
What file do you want to CREATE or UPDATE?
What function do you want to CREATE or UPDATE?
What are details you want to add to drive the code changes?
\```

2. [Second task]

\```
...
\```

## Validation Gates

- [A list of items to validate completion of this plan]

## Rules and requirements
- ALWAYS update the source plan after each task and keep our source-of-truth up-to-date
- MAINTAINABILITY above all else
- ALWAYS follow KISS (keep it simple stupid), AVOID over engineering
- ALWAYS use `dev` or `task` (go-task) commands over manual commands, if needed, prompt the user for clarification on building new commands
```

## Output Format

- Output as markdown to `./tmp/plan/<feature_name>-plan.md`
- After creation, inform the user of where to find the plan and provide a brief summary

## User Interaction

After completing initial research, present findings to the user and confirm:

- The scope of the plan
- Patterns to follow
- Implementation approach
- Validation criteria

If the user answers with "continue", proceed with plan creation without additional user input.

## Context Prioritization

A successful plan must include comprehensive context through specific references to:

- Files in the codebase
- Web search results and URLs
- Documentation
- External resources
- Example implementations
- Validation criteria

## Rules

- ONLY generate the plan document and DO NOT implement any code changes
- DO NOT generate any other documents like PR descriptions
- NEVER create multiple plans for the same feature / task
- ALWAYS use a single plan as the source of truth
- MAINTAINABILITY above all else
- ALWAYS follow KISS (keep it simple stupid), AVOID over engineering

A plan is requirement doc + curated codebase intelligence + agent/runbook -- the minimum viable packet an AI needs to ship production-ready code on the first pass.
