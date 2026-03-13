# Multi-Model Critic Consensus

How we filter false positives from AI-generated findings using independent multi-model verification.

## Problem

A single model reviewing code or plans produces false positives -- hallucinated bugs, inflated severities, speculative concerns. These waste human attention and erode trust.

## Approach

Three independent critic agents (Claude, GPT, Gemini) evaluate each finding in parallel. A finding survives only with >=2/3 KEEP votes. The critics are domain-agnostic; each calling skill passes domain-specific KEEP/REJECT criteria via the Task prompt.

```
Skill (pr-reviewer, plan-reviewer, plan-generator)
  -> Researcher (investigates claims, returns evidence + confidence)
  -> 3x Critics in parallel (vote KEEP/REJECT against caller-provided criteria)
  -> Consensus filter (>=2 KEEP = survives)
```

## Architecture

| Component | Role | Location |
|-----------|------|----------|
| Researcher | Deep investigation, returns evidence with confidence levels | `agents/researcher.md` |
| Critic (x3) | Votes KEEP/REJECT against provided criteria | `agents/critic/{claude,gpt,gemini}.md` |
| Calling skill | Provides domain-specific criteria in Task prompt | `skills/{pr-reviewer,plan-reviewer,plan-generator}/SKILL.md` |

### Separation of concerns

Critics contain only the investigation and voting protocol. Domain-specific criteria (what constitutes a real PR bug vs. a valid plan concern) live in the calling skill's Task prompt. This makes critics reusable across skills without modification.

### Researcher agent

Before critics vote, the researcher agent investigates claims against actual source material. Only findings with CERTAIN or LIKELY confidence proceed to critic evaluation. The researcher is invoked by both the calling skill (for initial investigation) and by critics (when they need independent verification).

## Per-Skill Usage

| Skill | What gets investigated | What gets critic-filtered | Criteria type |
|-------|----------------------|--------------------------|---------------|
| pr-reviewer | Each potential bug/vuln finding | All findings from Stage 2 | PR-specific (real bug, introduced by PR, provable impact) |
| plan-reviewer | Factual claims in Correctness dimension | Blocker and Concern findings only | Plan-specific (real issue, verified evidence, correct severity) |
| plan-generator | Codebase patterns during research | Verifiable claims before output | Claim correctness (file exists, API matches, code valid) |

## Batching

- <=5 findings: evaluate individually (3 Task calls each)
- &gt;5 findings: batch all into one prompt per critic (3 Task calls total)

## Cost

Each critic invocation is one Task call per model. A review with 5 findings = 15 critic calls. Batching reduces this to 3 calls for >5 findings. The researcher adds 1 call per investigation (runs in its own 30-step session).
