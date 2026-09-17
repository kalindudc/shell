---
name: critique
description: On-demand multi-model critic consensus for arbitrary concerns
---

# Critique Skill

## Purpose

Evaluate user-provided concerns against source evidence, using multi-model critic consensus when the configured models can be independently verified. Verify simple claims inline and delegate substantial unresolved questions; do not create a researcher session per concern by default.

Goal: "Is this concern real, evidenced, and significant -- or speculative noise?"

## Process

### 0. Pre-check

Resolve `SKIP_CRITIQUE` from applicable context or the environment once; never read `.env` to find it. If it is `true` or `1`, return "Critique skill skipped due to SKIP_CRITIQUE flag." The wrapper does not repeat this preflight.

```bash
printf '%s\n' "${SKIP_CRITIQUE-}"
```

### 1. Parse concerns

Extract individual concerns from user input. Each concern should have:
- A description (what the user is worried about)
- Optional context references (file paths, URLs, code snippets, PR numbers)
- Optional severity the user believes it has

If no concerns were supplied, ask once after honoring the opt-out. Split multiple concerns where their boundaries are clear; ask only when ambiguity materially affects scope or correctness.

### 2. Investigate the concern batch

Deduplicate related concerns and reuse applicable revision-scoped evidence. Verify mechanical facts inline. Delegate only unresolved substantial questions that benefit from independent context, grouping concerns that share sources.

Task-array template (fill in the actual bounded scope and evidence requirements):

```json
{"tasks":[{"agent":"researcher","task":"Verify <unresolved concern batch> in <verified paths/revision> without edits; return confidence, file:line evidence, and remaining gaps."}]}
```

Use the same evidence/confidence standard for inline and delegated work: CERTAIN or LIKELY concerns proceed; POSSIBLE or DECLINE remain explicitly "Insufficient Evidence." No surviving concerns means no critic sessions. If delegation fails, continue inline only when the missing evidence is obtainable within scope; do not invent another workflow.

### 3. Multi-model critic consensus

An empty screened batch skips this entire stage, including configuration/prompt reads.

1. Read or reuse `~/.agents/skills/critique/critics.yml` and `critic-prompt.md` once for this review. Establish the configured critic count N and whether the runtime can provide verified actual model identities. Configuration labels or a model's self-identification are not dispatch evidence.
2. If configuration, dispatch, or identity evidence is unavailable, report consensus as unavailable/unverified and retain directly supported concerns for human review, labeled not consensus-filtered. Do not spawn probes or compensating review loops just to manufacture diversity.
3. Send the evidence-backed concern batch in one `spawn` tasks array, one task per critic model. Each task explicitly sets its configured model and includes the shared prompt, concern IDs, evidence, criteria, and bounded source scope. Require KEEP/REJECT/ABSTAIN with rationale per concern. Split only when a demonstrated context limit requires it; record the actual session count.
4. To label a concern multi-model validated, require KEEP from at least `max(2, floor(N / 2) + 1)` distinct, verified actual model identities. Count one vote per actual model. Abstentions, duplicate identities, timeouts, missing verification, and tool failures never lower this quorum.
5. Distinguish evidence-based rejection from insufficient verification/tool failure without rewriting votes. If evidence contradicts votes, inspect the specific conflict and report unresolved disagreement; do not rerun until a desired vote appears. Agreement is a filter, not factual proof.
6. Scope the output to the reviewed revisions/snapshots. Refresh only evidence invalidated by relevant changes, lost/truncated context, or a material freshness requirement; unchanged valid evidence does not require another review pass.

#### Evaluation Criteria

REJECT if any of these apply:
- Concern is purely speculative without concrete evidence
- Concern's claims contradict actual source material (critic verified)
- Concern is a subjective preference, not a factual issue
- Concern calls intended behavior a defect without evidence of conflict with the user's objectives or concrete harm; documented intent alone does not make a protocol efficient or correct
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
- Cap the complete filename, including `-analysis.md`, at 128 characters; shorten the sanitized label as needed

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

## Not Consensus-Filtered
<Directly source-verified concerns whose consensus was unavailable/unverified/below quorum, with evidence and the specific limitation. Omit when empty.>

## Filtered Concerns
<N> concerns filtered by critic consensus:
- <title> (votes: <votes>/<critics> KEEP -- <primary rejection reason>)

## Researcher Notes
[Optional -- include when researcher investigation surfaces valuable factual findings separate from the concern's validity. Omit this section if no additional findings emerged.]

## Insufficient Evidence
<N> concerns skipped (researcher confidence below LIKELY):
- <title> -- <researcher notes on why evidence was insufficient>
```

Omit empty sections. Honor an explicit answer-only/no-artifact request by returning the structured review inline; otherwise retain the configured report file. Copy to clipboard only within the requested output scope. When consensus is unavailable or below quorum, include directly supported concerns in a clearly labeled not-consensus-filtered section rather than claiming they were validated.

## Self-Improvement

Capture feedback only for concrete, novel, reusable evidence from this task and within its authorized scope. Ordinary success or restating existing guidance starts no notes read, observer, or promotion.

When capture is justified, the current agent owns the gate: resolve `SKIP_SKILL_NOTES` from the environment only (never `.env`); `1` or `true` disables notes. Otherwise use the `improve-skills` Fast Loop. Reuse applicable evidence; one owner and at most one entry per skill/session. A delegated observer receives `notes_enabled=true`, the target, and the concrete observation.

## Rules

- NEVER modify source files -- this skill is read-only analysis
- ALWAYS investigate concerns against actual source material before critic evaluation
- ALWAYS include researcher confidence level for transparency
- Claim multi-model validation only when the fixed distinct-model quorum is met. Report unavailable consensus and directly supported unfiltered concerns honestly; never substitute votes for source evidence.
- If no concerns are validated, output the analysis with empty Validated section
- Keep output terse -- explain "why" not "what"
- NEVER fabricate evidence -- if it can't be verified, report it as Insufficient Evidence
