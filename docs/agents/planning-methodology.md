# Planning Methodology

How and why we use structured implementation plans to guide AI coding agents.

## Why Plan?

Plans exist because AI agents fail predictably without them: they drift from objectives, make inconsistent architectural decisions, skip validation, and produce code that doesn't integrate. A plan is a structured prompt that supplies an agent with everything it needs to deliver a vertical slice of working software.

Three layers make a plan AI-critical (as opposed to a generic project plan):

- **Context** -- precise file paths, library versions, code snippets. Plans are standalone; all relevant context is embedded directly.
- **Implementation Strategy** -- specific libraries, code standards, repo patterns, architectural decisions. The agent shouldn't have to infer these.
- **Validation Gates** -- deterministic checks (build, test, lint). The agent knows when it's done.

## The Pipeline

```
/plan -> /plan-review -> /implement
```

Each stage has a skill that defines the methodology and a command that provides the entry point. Review is optional but recommended for complex plans.

| Stage | Skill | Command | Output |
|-------|-------|---------|--------|
| Generate | `plan-generator` | `/plan` | `./tmp/plan/<name>-plan.md` |
| Review | `plan-reviewer` | `/plan-review` | `./tmp/plan-review/<name>-review.md` |
| Implement | `implementer` | `/implement` | Code changes + plan marked completed |

### Generate

The plan-generator follows a 4-step research process before writing:

1. **Documentation review** -- check `**/docs/` for relevant context
2. **Web research** -- library docs, sample implementations
3. **Template analysis** -- review past plans in `./tmp/plan/` for consistency
4. **Codebase exploration** -- identify files, patterns, conventions to follow

If research is unambiguous, proceed. If ambiguous, stop and ask the user.

### Review

The plan-reviewer evaluates plans across 7 dimensions adapted from formal engineering review practices:

| Dimension | Source | Core Question |
|-----------|--------|---------------|
| Completeness | NASA PDR | Are all objectives traced to tasks? Any gaps? |
| Correctness | Fagan Inspection | Do referenced files, APIs, libraries actually exist? |
| Feasibility | NASA PDR | Can this approach achieve the stated objectives? |
| Risk | ATAM | What are the sensitivity points and unacknowledged risks? |
| Tradeoffs | ATAM | Were alternatives considered? Is the rationale sound? |
| Consistency | IEEE 1028 | Do sections contradict each other? |
| Testability | NASA TRR | Are validation gates deterministic and executable? |

Verification is active: the reviewer reads files, queries ASTs, and fetches URLs to verify claims. Findings are labeled by severity (Blocker / Concern / Suggestion / Nit / Praise) and the verdict is Approve, Request Changes, or Reject.

### Implement

The implementer executes Low-Level Tasks in strict order, following a per-task loop:

1. **Parse** -- read the task, identify targets
2. **Context** -- read all referenced files
3. **Implement** -- make changes
4. **Verify** -- run tests/build for that task
5. **Record** -- mark task completed, note deviations

Checkpoints every 3 tasks verify alignment with the original objective. Up to 3 retries on verification failure, then stop and report to the user.

## Research Foundation

The planning and review methodology draws from established engineering review practices:

| Source | Key Contribution |
|--------|-----------------|
| **Fagan Inspection** (IBM, 1976) | Structured inspection with entry/exit criteria and defect categorization. 80-90% defect detection rates. The cost to fix a defect in review is 10-100x less than in production. |
| **IEEE 1028-2008** | Generic formal review process: entry evaluation, preparation, examination, rework, exit. Distinguishes technical reviews (suitability) from inspections (defects). |
| **ATAM** (CMU SEI, 2000) | Architecture evaluation via quality attribute scenarios. Surfaces sensitivity points and tradeoffs. |
| **NASA PDR** (NPR 7123.1B) | Design review objectives: requirements complete, design meets requirements, sufficient maturity to proceed, risks identified. |
| **Bacchelli & Bird** (ICSE 2013) | The #1 code review activity is *understanding* the change. Reviews provide knowledge transfer and alternatives, not just bug finding. |

## What Makes a Good Plan

**Strong plans:**
- Clear traceability: every objective maps to tasks maps to validation gates
- Concrete file paths in Context (not vague references like "relevant files")
- Tasks with explicit `CREATE` or `UPDATE` blocks specifying target files
- Implementation Notes explaining *why* (decisions, tradeoffs), not just *what*
- Validation Gates that are deterministic and executable (a command, not "verify it works")

**Weak plans:**
- Objectives with no corresponding tasks (gaps)
- Tasks that don't serve any stated objective (orphans)
- References to files, APIs, or libraries that don't exist
- Missing or non-deterministic Validation Gates
- Implementation Notes that repeat what the code already shows

## Plan Sizing

A plan should be implementable in a single session. If it can't be, split it into a plan stack -- multiple independent plans in a directory, each self-contained. Plan stacks are a last resort; always prefer a single plan.
