---
name: critique
description: On-demand multi-model critic consensus for arbitrary concerns -- investigate, evaluate, and filter
---

# Critique Skill

## Purpose

Evaluate user-provided concerns through multi-model critic consensus. Takes one or more
concerns (about code, architecture, design, process, or any artifact), investigates each
via the researcher agent, then filters through multi-model critic consensus to separate real issues
from speculative or unfounded worries.

Goal: "Is this concern real, evidenced, and significant -- or speculative noise?"

## Process

### 1. Parse concerns

Extract individual concerns from user input. Each concern should have:
- A description (what the user is worried about)
- Optional context references (file paths, URLs, code snippets, PR numbers)
- Optional severity the user believes it has

If the user provides a single block of text with multiple concerns, split them into
individual items. If boundaries are ambiguous, ask the user to clarify.

### 2. Investigate each concern

For each concern, invoke the researcher agent:
  Task(subagent_type="researcher", prompt=<concern description + context references + codebase path>)

The researcher investigates against actual source material and returns findings with
confidence levels (CERTAIN/LIKELY/POSSIBLE/DECLINE) and verbatim evidence.

Only concerns with CERTAIN or LIKELY confidence proceed to Step 3. Concerns rated
POSSIBLE or DECLINE are reported in the output as "Insufficient Evidence" with the
researcher's notes -- they skip critic evaluation.

If the researcher fails or times out, fall back to inline verification:
read the referenced files, trace dependencies, and verify claims directly.

### 3. Multi-model critic consensus

Invoke the consensus orchestrator with the investigated concerns and the following criteria:

  Task(subagent_type="consensus", prompt=<concerns + evidence + codebase path + criteria below>)

  ## Evaluation Criteria

  REJECT if any of these apply:
  - Concern is purely speculative without concrete evidence
  - Concern's claims contradict actual source material (critic verified)
  - Concern is a subjective preference, not a factual issue
  - Concern describes intended/documented behavior as a problem
  - Concern is about a theoretical scenario with no plausible trigger path
  - Evidence does not support the stated severity or impact

  KEEP only if ALL true:
  - Concern identifies a REAL issue (verifiable against source material)
  - Evidence is VERIFIED against actual code, docs, or artifacts
  - Impact is CONCRETE and describable (not hypothetical)

Note: The effective critic panel is frequently 3/4 rather than 4/4 due to timeouts (particularly GPT). This is normal operation -- apply dynamic consensus thresholds (e.g., 2/3 KEEP when one critic abstains) and note abstentions in the output.

### 4. Output

Write structured analysis to `./tmp/critics/<label>-analysis.md`.

The label is derived from user input:
- If user provides a label/topic, sanitize it (lowercase, hyphens, no special chars)
- If no label, use ISO date-time: `YYYYMMDD-HHMMSS`
- Cap filename (excluding `-analysis.md` suffix) at 128 characters total

```markdown
# Concerns Analysis: <label>

**Date:** <date> | **Concerns:** <total> | **Validated:** <survived count> | **Filtered:** <filtered count> | **Insufficient Evidence:** <skipped count>

## Summary
<2-3 sentences: what was analyzed, consensus outcome, cost stats>
e.g., "3 of 5 concerns validated by critic consensus. 1 filtered (speculative), 1 skipped (insufficient evidence). 9 critic sessions spawned."

## Validated Concerns

### <Concern title>
- **Description:** <what the concern is about>
- **Evidence:** <researcher findings with file:line references>
- **Impact:** <concrete impact assessment>
- **Critic consensus:** <votes>/<critics> KEEP
- **Recommendation:** <suggested action>

## Filtered Concerns
<N> concerns filtered by critic consensus:
- <title> (votes: <votes>/<critics> KEEP -- <primary rejection reason>)

## Researcher Notes
[Optional -- include when researcher investigation surfaces valuable factual findings
separate from the concern's validity. These are concrete findings worth preserving even
when the parent concern was filtered or skipped. Omit this section if no additional
findings emerged.]

## Insufficient Evidence
<N> concerns skipped (researcher confidence below LIKELY):
- <title> -- <researcher notes on why evidence was insufficient>
```

Omit empty sections. Copy to clipboard if `pbcopy`/`xclip` available.

## Self-Improvement

After execution, use `@skill-improver` to capture observations. Before execution, check `SKILL_NOTES.md` for known edge cases.

## Rules

- NEVER modify source files -- this skill is read-only analysis
- ALWAYS investigate concerns against actual source material before critic evaluation
- ALWAYS include researcher confidence level for transparency
- No concern survives without majority critic KEEP votes
- If no concerns are validated, output the analysis with empty Validated section
- Keep output terse -- explain "why" not "what"
- NEVER fabricate evidence -- if it can't be verified, report it as Insufficient Evidence
