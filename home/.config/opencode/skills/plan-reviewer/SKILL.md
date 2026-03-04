---
name: plan-reviewer
description: Perform thorough, structured reviews of engineering implementation plans with claim verification, research validation, and risk assessment
---

# Plan Reviewer Skill

## Purpose

Perform thorough reviews of engineering implementation plans before they proceed to implementation.

The reviewer's goal: "Is this plan ready to guide implementation? Will following it produce working software that meets its stated objectives?"

Output is a structured review report -- the user decides whether to approve, revise, or reject the plan. This skill fills the gap between `/global/plan` and `/global/implement` in the workflow.

## Entry Criteria

Before beginning review, verify the plan meets minimum structural requirements (see `docs/planning-methodology.md` for plan structure and quality signals):

- Plan file exists and is readable markdown
- Plan has a High-Level Objective section
- Plan has Low-Level Tasks section with at least one task
- Plan has a Context section (Beginning and/or Ending context)

If entry criteria fail, STOP and report which criteria failed. Do not review an incomplete plan.

## Process

### 1. Ingest the plan

- Read the plan file completely
- Identify: High-Level Objective, Mid-Level Objectives, Implementation Notes, Context, Low-Level Tasks, Validation Gates
- Note any external references (research, documentation URLs, library docs) for verification in step 3

### 2. Understand the intent

Understanding is the #1 review activity.

- What problem is the plan solving? Is it clearly stated?
- What approach was chosen? Were alternatives considered?
- What is the expected end state? Is it clearly defined?

### 3. Review using structured checklist

Evaluate each dimension. Each produces findings with severity labels. Skip dimensions that don't apply.

**Completeness** ("ensure requirements are complete and flowdown is adequate"):
- Are all objectives traced to Low-Level Tasks? Any gaps or orphan tasks?
- Do Beginning context files actually exist? (Use Read tool to verify)
- Are task dependencies identified?

**Correctness** ("compare output against requirements"):
- Do referenced files, functions, classes exist? (Use Read, ast_query, Glob)
- Do referenced libraries/APIs exist and support described usage? Check installed source/type definitions as ground truth (docs omit signature details). Use webfetch for external APIs.
- Are code snippets syntactically valid?
- If the plan cites research, verify claims match sources (use webfetch)

**Feasibility** ("show proposed design meets requirements"):
- Can the approach achieve the stated objectives?
- Are there unaddressed technical blockers?
- Are task estimates reasonable for a single implementation session?

**Risk** ("identify sensitivity points and risks"):
- Are risks explicitly identified? What are unacknowledged risks?
- Where would a small error cascade? Single points of failure?
- Is there a fallback if a key assumption proves wrong?

**Tradeoffs** ("document tradeoffs and their rationale"):
- Were alternatives considered? Is the rationale for the chosen approach sound?
- Does the plan over-engineer (KISS violation) or under-engineer (missing edge cases)?

**Consistency** ("identify discrepancies"):
- Do Low-Level Tasks align with Implementation Notes?
- Are there contradictions between sections? Is terminology consistent?
- Do Ending context files match what tasks would produce?

**Testability** ("ensure verification methods are described"):
- Are Validation Gates present and deterministic?
- Can each gate actually be executed?
- Would passing gates demonstrate objectives are met?

### 4. Categorize and label findings

Each finding gets:
- **Severity**: Blocker | Concern | Suggestion | Nit | Praise
  - Blocker: Plan cannot proceed (incorrect assumptions, missing tasks, non-existent APIs)
  - Concern: Should be addressed, significant impact on success
  - Suggestion: Would improve the plan but not blocking
  - Nit: Minor wording, formatting, or style issue
  - Praise: Something done well (thorough research, good risk assessment)
- **Dimension**: Which review dimension the finding belongs to
- **Brief explanation** of why (not just what), with evidence from verification

### 5. Determine verdict

- **Approve**: No blockers, concerns are minor. Plan is ready for `/global/implement`.
- **Request Changes**: Blockers or significant concerns. Plan needs revision.
- **Reject**: Fundamental issues -- incorrect assumptions, wrong approach, flawed problem statement. Needs re-planning.

## Output

Write structured review to `./tmp/plan-review/<plan-name>-review.md`:

```
# Plan Review: <plan title>
**Source:** <path> | **Verdict:** Approve / Request Changes / Reject | **Date:** <date>

## Summary
[1-3 sentences: what the plan proposes, overall assessment]

## Findings
### Blockers
- [Blocker] [Dimension] -- description (evidence: ...)
### Concerns
- [Concern] [Dimension] -- description (evidence: ...)
### Suggestions
- [Suggestion] [Dimension] -- description
### Praise
- [Praise] [Dimension] -- description

## Checklist
- [x/~/!] Completeness, Correctness, Feasibility, Risk, Tradeoffs, Consistency, Testability
(x = pass, ~ = minor issues, ! = significant issues)

## Verification Log
[Claims verified: files checked, URLs fetched, AST queries run]

## Recommendation
[If Request Changes or Reject: what needs to change and why]
```

Omit empty severity sections. Target: readable in under 5 minutes. Copy to clipboard if `pbcopy`/`xclip` available.

## Self-Improvement

After execution, use `@skill-improver` to capture observations. Before execution, check `SKILL_NOTES.md`.

## Rules

- NEVER approve a plan without verifying at least the Correctness dimension (file existence, API claims)
- ALWAYS read the plan completely before beginning evaluation
- ALWAYS verify factual claims -- do not take the plan at face value
- ALWAYS label finding severity and dimension explicitly
- ALWAYS explain "why" for each finding with evidence from verification
- ALWAYS include praise when warranted -- good plans deserve recognition
- NEVER reject a plan without providing specific guidance on what needs to change
- FOLLOW KISS -- skip checklist dimensions that don't apply to the plan
