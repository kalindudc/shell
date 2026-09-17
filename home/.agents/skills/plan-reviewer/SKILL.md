---
name: plan-reviewer
description: Perform thorough, structured reviews of engineering implementation plans with claim verification, research validation, and risk assessment
---

# Plan Reviewer Skill

## Purpose

Perform thorough reviews of engineering implementation plans before they proceed to implementation.

The reviewer's goal: "Is this plan ready to guide implementation? Will following it produce working software that meets its stated objectives?"

Output is a structured review report -- the user decides whether to approve, revise, or reject the plan. This skill fills the gap between plan creation and implementation in the workflow.

## Entry Criteria

Use the user's explicit Markdown file or Cortex task ID, including an unambiguous source already identified in the conversation. If no unique source is supplied, ask once. An invalid source is a specific lookup error, not permission to discover or substitute another plan.

Verify these embedded minimum structural requirements; no external methodology file is required:

- The explicitly named file exists and is readable, or the named Cortex task contains a readable Markdown body
- Plan has a High-Level Objective section
- Plan has Low-Level Tasks section with at least one task
- Plan has a Context section (Beginning and/or Ending context)

If entry criteria fail but the document contains plan-like intent (objectives, recommendations, tasks), proceed with adapted dimensions rather than rejecting outright. Otherwise, STOP and report which criteria failed.

## Process

### 1. Ingest the plan

- Read the chosen plan completely once and retain its source identity and reviewed snapshot. For a Cortex source, use `cortex show <id> --json` once and inspect its body; reviewing a draft does not authorize implementation or require the implementer's open-status gate.
- Identify: High-Level Objective, Mid-Level Objectives, Implementation Notes, Context, Low-Level Tasks, Validation Gates.
- Use applicable source/verification context already available; reload only after a relevant change, missing/truncated context, or material freshness need. Do not mutate the plan body or its status during review.

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

Verify mechanical claims inline and reuse applicable evidence. Delegate only unresolved substantial factual questions in a bounded batch, not the entire verification checklist automatically.

```json
{"tasks":[{"agent":"researcher","task":"Verify <unresolved claims> against <plan snapshot and verified source paths>; return confidence and file:line evidence without edits."}]}
```

Apply these checks to inline and delegated findings. If delegation is unavailable, continue inline only where the required evidence can be obtained within scope:
- Do referenced files, functions, classes exist? (Use Read, ast_query, Glob). Always read the actual pattern files being referenced and at least one real data file -- plans frequently describe idealized schemas rather than actual data shapes.
- Do referenced libraries/APIs exist and support the described usage? Check actual source/type definitions. For external behavior, use authoritative version-matched documentation through registered tools; reuse applicable verified source evidence rather than refetching every cited URL by default.
- Are code snippets syntactically valid?
- For quantitative claims (element counts, line counts, test counts), verify directly against the source or a real generated output rather than trusting listed enumerations. When a plan hardcodes emitted/generated paths, compare the list and count against that output; if recommending a fix, prefer dynamic discovery over replacing one hardcoded enumeration with another.
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

Screen and deduplicate Blockers/Concerns before this stage; an empty batch skips the entire stage, including configuration/prompt reads. Read or reuse `~/.agents/skills/critique/critics.yml` and `critic-prompt.md` once. If configuration, model dispatch, or actual identity verification is unavailable, report consensus unavailable/unverified and retain directly supported findings labeled not consensus-filtered; do not invent a consensus agent or probe loop.

1. Send the screened Blocker/Concern batch once to each configured critic in a single `spawn` tasks array, with explicit model, shared evaluation prompt, finding IDs/evidence, plan snapshot, and bounded source paths. Require KEEP/REJECT/ABSTAIN with rationale per finding. Split only for a demonstrated context limit.
2. Let N be the configured critic count. Multi-model validation requires KEEP from `max(2, floor(N / 2) + 1)` distinct, verified actual model identities, one vote per model. Requested labels or model self-reports are not identity verification.
3. Abstentions, duplicate identities, timeouts, unavailable verification, and tool failures do not lower the quorum. Report below-quorum findings as not consensus-filtered; do not erase direct evidence or claim agreement that was not established.
4. Inspect concrete conflicts between votes and source evidence and report unresolved disagreement rather than rerunning to obtain favorable votes. Reuse applicable evidence; refresh only after relevant changes or a material freshness/context gap. Report actual critic-session counts and limitations.

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

- Approve: No blockers, concerns are minor. Plan is ready for implementation.
- Request Changes: Blockers or significant concerns. Plan needs revision.
- Reject: Fundamental issues -- incorrect assumptions, wrong approach, flawed problem statement. Needs re-planning.

## Output

Keep the configured report at `./tmp/plan-review/<plan-name>-review.md` unless the user explicitly requests answer-only/no artifact output. Use `cortex-<id>` for a Cortex source's filename stem, or a sanitized file stem; cap the complete filename at 128 characters. Identify the actual source and reviewed snapshot. Never modify the source plan or create a replacement plan.

Use this structured review format:

```
# Plan Review: <plan title>
**Source:** <file or Cortex task ID; reviewed snapshot> | **Verdict:** Approve / Request Changes / Reject | **Date:** <date>

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

Omit empty severity sections and distinguish consensus-filtered findings from directly verified findings whose consensus was unavailable/below quorum. Target: readable in under 5 minutes. Copy to clipboard only within the requested output scope.

## Self-Improvement

Capture feedback only for concrete, novel, reusable evidence from this task and within its authorized scope. Ordinary success or restating existing guidance starts no notes read, observer, or promotion.

When capture is justified, the current agent owns the gate: resolve `SKIP_SKILL_NOTES` from the environment only (never `.env`); `1` or `true` disables notes. Otherwise use the `improve-skills` Fast Loop. Reuse applicable evidence; one owner and at most one entry per skill/session. A delegated observer receives `notes_enabled=true`, the target, and the concrete observation.

## Rules

- NEVER approve a plan without verifying at least the Correctness dimension (file existence, API claims)
- Read the chosen plan completely once; reuse that snapshot unless relevant changes or context loss invalidate it. Honor explicit input/output scope and never discover or mutate an unrelated plan.
- ALWAYS verify factual claims -- do not take the plan at face value
- ALWAYS label finding severity and dimension explicitly
- ALWAYS explain "why" for each finding with evidence from verification
- ALWAYS include praise when warranted -- good plans deserve recognition
- NEVER reject a plan without providing specific guidance on what needs to change
- FOLLOW KISS -- skip checklist dimensions that don't apply to the plan
