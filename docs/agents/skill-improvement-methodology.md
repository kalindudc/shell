# Skill Improvement Methodology

Self-improving instruction files for LLM coding agents via a two-speed feedback loop.

## Overview

Each skill is a pair of markdown files:

- **SKILL.md** -- agent instructions, capped at 150 lines (instruction-following degrades beyond this)
- **SKILL_NOTES.md** -- structured observation log, append-only

| Skill | Purpose | Lines | Observations |
|---|---|---|---|
| plan-generator | Produce implementation plans | 136 | 5 |
| implementer | Execute plans with verification | 150 | 2 |
| pr-description-generator | Generate PR descriptions | 137 | 12 |
| pr-reviewer | Review PRs with categorized findings | 116 | 4 |
| codebase-explorer | Map unfamiliar codebases | 64 | 0 |
| debugger | Scientific debugging | 74 | 0 |
| skill-improver | Meta-skill: improve other skills | 60 | 0 |

## Feedback Loop

### Fast Loop (automated)

After every skill execution, a sandboxed subagent (`@skill-improver`) appends an observation to SKILL_NOTES.md:

```markdown
### 2026-03-02 | Successful Pattern | pr-description-generator
**Context:** Generated PR desc for a config-only change.
**Observation:** Testing section was thin -- no source or test files to reference.
**Takeaway:** Omit Testing section when diff contains no source/test files.
**Actionability:** ready-to-promote
```

Subagent constraints: can only edit `*SKILL_NOTES.md`, temperature 0.1, 10-step budget, no bash/web access.

Observations are triaged on capture: `ready-to-promote` | `needs-more-data` | `question-for-user`.

Categories: Edge Cases, Successful Patterns, Open Questions, Deviations, Tool Limitations.

### Slow Loop (human-gated)

`/improve-skill` reviews accumulated notes and proposes changes to SKILL.md. Promotion hierarchy:

1. **Generalize** (preferred) -- collapse edge cases into one principle
2. **Replace** -- new principle supersedes old
3. **Compress** -- same meaning, fewer words
4. **Append** (last resort) -- genuinely new, no overlap

Signal-to-noise check: *"If I removed this line, would the agent behave differently?"*

### Governance

`/skill-health` audits line counts, word counts, entry age, and flags skills approaching the 150-line ceiling.

## Metrics (7 days: Feb 25 -- Mar 3, 2026)

### Activity

| Metric | Value |
|---|---|
| Commits touching skill files | 13 (of 222 total) |
| Observations captured | 23 |
| Promoted to SKILL.md | 4 (17%) |
| Ready for promotion | 10 (43%) |
| Accumulating data | 7 (30%) |
| Open questions | 1 (4%) |
| Total SKILL.md lines (all skills) | 737 |
| Total SKILL.md words (all skills) | 5,313 |

### Compression

Skills got smaller while gaining capabilities:

| Skill | Initial | Current | Delta |
|---|---|---|---|
| implementer | 230 | 150 | **-35%** |
| plan-generator | 155 | 136 | **-12%** |
| pr-description-generator | 141 | 137 | **-3%** |

The implementer lost 80 lines by replacing verbose procedures with principles (14-line task extraction -> 4 lines, 10-line retry pseudocode -> 1 sentence, 12 rules -> 6) while adding tool integrations and behavioral rules.

### Observation Distribution

```
pr-description-generator  ████████████  12 (52%)
plan-generator            █████          5 (22%)
pr-reviewer               ████           4 (17%)
implementer               ██             2 (9%)
```

Feedback density correlates with execution frequency. Three skills with zero observations are used less often.

### Promotion Example

The "omit Testing for docs PRs" rule:

1. Feb 27: *"Testing section thin for docs-only PR."* -> `ready-to-promote`
2. Mar 2: *"Config-only PR also had sparse Testing."* -> `ready-to-promote`
3. Mar 3: Third data point. All three promoted into one SKILL.md line.

3 observations -> 1 instruction. 4 days from first observation to promotion.

### Timeline

```
Feb 25  Skills created (implementer: 230 lines, plan-gen: 155, pr-desc: 141)
Feb 26  First compression wave; explorer + debugger added; tool integrations
Feb 27  Feedback loop built (skill-improver subagent, skill-health command)
Mar 02  SKILL_NOTES format standardized; actionability triage added
Mar 03  pr-reviewer created (pre-standardized); first 4 promotions
```

## Architecture

```
  Commands              Skills                  Feedback
  ┌───────────┐          ┌────────────────┐
  │ /plan     │─────────>│ SKILL.md       │
  │ /implement│─────────>│ (instructions) │
  │ /pr-desc  │─────────>│                │
  │ ...       │          └───────┬────────┘
  └───────────┘                  │ after execution
                                 v
                       @skill-improver ──> SKILL_NOTES.md
                       (sandboxed)        (observations)
                                                 │
                                  /improve-skill │ (human-gated)
                                                 v
                                          SKILL.md updated
                                          (150-line ceiling)
```
