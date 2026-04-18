---
name: critique
description: On-demand multi-model critic consensus for arbitrary concerns
---

## Purpose

Evaluate user-provided concerns through multi-model critic consensus. Takes one or more concerns (about code, architecture, design, process, or any artifact), investigates each via the researcher agent, then filters through multi-model critic consensus to separate real issues from speculative or unfounded worries.

Goal: "Is this concern real, evidenced, and significant -- or speculative noise?"

## Process

### 0. Pre-check

If SKIP_CRITIQUE=true or SKIP_CRITIQUE=1 environment flag is set, then skip all steps and exit immediately with a message: "Critique skill skipped due to SKIP_CRITIQUE flag."

```bash
env | grep -i "SKIP_CRITIQUE"

# or

cat ~/.env | grep -i "SKIP_CRITIQUE"
```

### 1. Parse concerns

Extract individual concerns from user input. Each concern should have:
- A description (what the user is worried about)
- Optional context references (file paths, URLs, code snippets, PR numbers)
- Optional severity the user believes it has

If the user provides a single block of text with multiple concerns, split them into individual items. If boundaries are ambiguous, ask the user to clarify.

### 2. Investigate each concern

For each concern, invoke the researcher agent using `spawn`:

```
spawn(agent: "researcher", task: "<concern description + context references + codebase path>")
```

The researcher investigates against actual source material and returns findings with confidence levels (CERTAIN/LIKELY/POSSIBLE/DECLINE) and verbatim evidence.

Only concerns with CERTAIN or LIKELY confidence proceed to Step 3. Concerns rated POSSIBLE or DECLINE are reported in the output as "Insufficient Evidence" with the researcher's notes -- they skip critic evaluation.

If the researcher fails or times out, fall back to inline verification: read the referenced files, trace dependencies, and verify claims directly.

### 3. Multi-model critic consensus

Invoke multi-model critic consensus:

1. Read `~/.agents/skills/critique/critics.yml` to get the available critic models
2. Read `~/.agents/skills/critique/critic-prompt.md` to get the shared evaluation prompt
3. For each investigated concern, construct a `spawn` call with `tasks` array -- one task per critic model.
  ALWAYS spawn all critics in parallel
  ALWAYS explicitly specify the model for each critic
  Each task's `task` field = the critic prompt + concern + evidence + evaluation criteria below.
  Each task's `model` field = the model identifier from critics.yml.
4. Collect results, extract KEEP/REJECT/ABSTAIN votes from each critic's response
5. Apply dynamic consensus: majority KEEP = validated. Adjust threshold when critics abstain/timeout (e.g., 2/3 KEEP when one critic abstains).

#### Evaluation Criteria

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

### 4. Output

Write structured analysis to `./tmp/critics/<label>-analysis.md`.

The label is derived from user input:
- If user provides a label/topic, sanitize it (lowercase, hyphens, no special chars)
- If no label, use ISO date-time: `YYYYMMDD-HHMMSS`
- Cap filename (excluding `-analysis.md` suffix) at 128 characters total

Use this output template:

```markdown
# Concerns Analysis: <label>

**Date:** <date> | **Concerns:** <total> | **Validated:** <survived count> | **Filtered:** <filtered count> | **Insufficient Evidence:** <skipped count>

## Summary
<2-3 sentences: what was analyzed, consensus outcome, cost stats>

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
[Optional -- include when researcher investigation surfaces valuable factual findings separate from the concern's validity. Omit this section if no additional findings emerged.]

## Insufficient Evidence
<N> concerns skipped (researcher confidence below LIKELY):
- <title> -- <researcher notes on why evidence was insufficient>
```

Omit empty sections. Copy to clipboard if `pbcopy`/`xclip` available.

## Self-Improvement

After execution, use `skill-improver` to capture observations. Before execution, check `SKILL_NOTES.md` for known edge cases.

## Rules

- NEVER modify source files -- this skill is read-only analysis
- ALWAYS investigate concerns against actual source material before critic evaluation
- ALWAYS include researcher confidence level for transparency
- No concern survives without majority critic KEEP votes
- If no concerns are validated, output the analysis with empty Validated section
- Keep output terse -- explain "why" not "what"
- NEVER fabricate evidence -- if it can't be verified, report it as Insufficient Evidence
