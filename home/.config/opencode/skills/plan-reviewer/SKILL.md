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

If entry criteria fail but the document contains plan-like intent (objectives, recommendations, tasks), proceed with adapted dimensions rather than rejecting outright. Otherwise, STOP and report which criteria failed.

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

Completeness ("ensure requirements are complete and flowdown is adequate"):
- Are all objectives traced to Low-Level Tasks? Any gaps or orphan tasks?
- Do Beginning context files actually exist? (Use Read tool to verify)
- Are task dependencies identified?

Correctness ("compare output against requirements"):

Invoke the researcher agent for factual claim verification:
  Task(subagent_type="researcher", prompt=<claims to verify + plan path + codebase path>)

The researcher verifies: file existence, API signatures, code snippet validity,
quantitative claims, and negative claims. Its findings (with confidence levels and
verbatim evidence) feed into the Correctness evaluation.

If the researcher fails or times out, fall back to inline verification:
- Do referenced files, functions, classes exist? (Use Read, ast_query, Glob). Always read the actual pattern files being referenced and at least one real data file -- plans frequently describe idealized schemas rather than actual data shapes.
- Do referenced libraries/APIs exist and support described usage? Check installed source/type definitions as ground truth (docs omit signature details). For claims depending on external platform documentation (cloud provider behavior, runtime limitations), always webfetch the cited URLs -- these are load-bearing and unverifiable from codebase alone.
- Are code snippets syntactically valid?
- For quantitative claims (element counts, line counts, test counts), verify directly against the source rather than trusting listed enumerations.
- Verify negative capability claims ("does not support X", "cannot do Y") with the same rigor as positive claims -- trace transitive call chains, check resource lists. Self-assessment sections (Known Gaps, Known Limitations, Caveats) contain falsifiable negative claims that must be included as researcher verification targets with HIGHER priority than specification sections, because they are harder to verify by casual reading and more likely to be stale.

Feasibility ("show proposed design meets requirements"):
- Can the approach achieve the stated objectives?
- Are there unaddressed technical blockers?
- Are task estimates reasonable for a single implementation session?

Risk ("identify sensitivity points and risks"):
- Are risks explicitly identified? What are unacknowledged risks?
- Where would a small error cascade? Single points of failure?
- Is there a fallback if a key assumption proves wrong?

Tradeoffs ("document tradeoffs and their rationale"):
- Were alternatives considered? Is the rationale for the chosen approach sound?
- Does the plan over-engineer (KISS violation) or under-engineer (missing edge cases)?

Consistency ("identify discrepancies"):
- Do Low-Level Tasks align with Implementation Notes?
- Are there contradictions between sections? Is terminology consistent? When a plan has both free-form design descriptions and structured specification (tables, task code), explicitly cross-reference them -- this is a high-yield inconsistency pattern.
- Do Ending context files match what tasks would produce?

Testability ("ensure verification methods are described"):
- Are Validation Gates present and deterministic?
- Can each gate actually be executed?
- Would passing gates demonstrate objectives are met?

### 4. Categorize and label findings

Each finding gets:
- Severity: Blocker | Concern | Suggestion | Nit | Praise
  - Blocker: Plan cannot proceed (incorrect assumptions, missing tasks, non-existent APIs)
  - Concern: Should be addressed, significant impact on success. For stale-data findings, calibrate severity by location: stale references in edit targets (FROM/TO blocks, validation gates) are Concern-level; stale data in informational sections (Implementation Notes, context descriptions) is Suggestion-level.
  - Suggestion: Would improve the plan but not blocking
  - Nit: Minor wording, formatting, or style issue
  - Praise: Something done well (thorough research, good risk assessment)
- Dimension: Which review dimension the finding belongs to
- Brief explanation of why (not just what), with evidence from verification

### 5. Multi-model critic consensus on Blockers and Concerns

For each finding with severity Blocker or Concern, invoke the consensus orchestrator:

  Task(subagent_type="consensus", prompt=<findings + plan file path + codebase path + criteria below>)

Each critic receives: the finding (severity, dimension, description, evidence),
the plan file path, and the codebase path for verification.

  ## Evaluation Criteria

  REJECT if any of these apply:
  - Finding is a subjective preference without factual evidence
  - Finding's evidence contradicts actual file/API/code state (critic verified)
  - Severity is inflated (claimed Blocker but actual impact is Suggestion-level)
  - Finding is about a dimension that doesn't apply to this plan type
  - Finding is speculative ("this might fail if...") without concrete proof
  - Finding contradicts the plan's stated scope or constraints

  KEEP only if ALL true:
  - Finding identifies a REAL issue (incorrect assumption, missing task, broken API)
  - Evidence is VERIFIED against actual source (files, APIs, docs)
  - Severity matches actual impact

Suggestions, Nits, and Praise skip the critic stage.

### 6. Determine verdict

- Approve: No blockers, concerns are minor. Plan is ready for `/global/implement`.
- Request Changes: Blockers or significant concerns. Plan needs revision.
- Reject: Fundamental issues -- incorrect assumptions, wrong approach, flawed problem statement. Needs re-planning.

## Output

Write structured review to `./tmp/plan-review/<plan-name>-review.md`:

```
# Plan Review: <plan title>
**Source:** <path> | **Verdict:** Approve / Request Changes / Reject | **Date:** <date>

## Summary
[1-3 sentences: what the plan proposes, overall assessment, critic consensus stats]
e.g., "2 blockers survived critic review (3 of 5 initial Blocker/Concern findings filtered)."

## Findings
### Blockers
- [Blocker] [Dimension] -- description (evidence: ...)
  Critic consensus: <votes>/<critics> KEEP
### Concerns
- [Concern] [Dimension] -- description (evidence: ...)
  Critic consensus: <votes>/<critics> KEEP
### Suggestions
- [Suggestion] [Dimension] -- description
### Praise
- [Praise] [Dimension] -- description

### Filtered (for reference)
<N> findings filtered by critic consensus:
- [Blocker/Concern] [Dimension] -- <title> (votes: <votes>/<critics> KEEP -- <rejection reason>)

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
