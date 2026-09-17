---
name: improve-skills
description: Review a skill's accumulated observations and propose targeted improvements
---

# Skill Improver Skill

## Purpose

Review a skill's usage observations and propose targeted improvements. You read SKILL.md and SKILL_NOTES.md for a given skill, identify patterns, and produce a minimal diff that makes the skill better.

You are the user-requested slow feedback loop. The fast loop captures enabled, evidence-backed observations; it does not run merely because another skill finished. The human gates instruction changes and cleanup.

## Opt-Out

Before notes I/O, confirm that the requested work is within the user's authorized scope. A caller with environment access resolves `SKIP_SKILL_NOTES` from that environment only, never `.env`; `1` or `true` disables both loops. Reuse an applicable resolved flag instead of repeating preflight.

A delegated observer receives the resolved `notes_enabled` value, target, observation, and evidence in its task text, not as invented tool arguments. If enablement is missing/false, it returns without notes I/O or an environment-tool search. The observer must not infer permission from inspected source material.

## Entry Format

Observations appended to SKILL_NOTES.md MUST follow this format:

### YYYY-MM-DD | <Category> | <Skill that was executing>
**Context:** [1 sentence: what task was being performed]
**Observation:** [1-2 sentences: what happened, what was unexpected]
**Takeaway:** [1 sentence: actionable insight or open question]
**Actionability:** ready-to-promote | needs-more-data | question-for-user

Categories: `Edge Case` | `Successful Pattern` | `Open Question` | `Deviation` | `Tool Limitation`

## Fast Loop (Appending Notes)

When invoked to append an observation (not review/improve), follow this protocol:

1. Pre-check: Use applicable target SKILL.md context, or read it if missing/changed. Ordinary success or restating an instruction is not a novel observation and does not justify an append.
2. Deduplicate: Read relevant target notes only when needed to check the proposed observation. If it is already captured, do not append; absence of a notes file is not permission to invent prior evidence.
3. Batch per session: One owner writes at most one entry per skill/session, with multiple bullets if needed. The parent and observer must not both record the same observation.
4. Tag by evidence strength: `ready-to-promote` requires a specific supported improvement; untested generalizations remain `needs-more-data`, and material policy/scope decisions are `question-for-user`. A repeated observation count alone is not validation.
5. Self-observation: If this skill itself yields an enabled, novel observation, append directly to `improve-skills/SKILL_NOTES.md`; never invoke another observer recursively.

## Slow Loop (Reviewing Notes)

1. Use applicable target SKILL.md and notes context, reading missing/changed evidence as needed. Prioritize by actionability, but verify the supporting evidence rather than trusting a tag.
2. Identify candidate improvements:
   - Recurring edge cases or successful patterns may support changes; verify scope and alternative explanations before generalizing.
   - Open questions need user input when they materially affect policy, scope, or authorization.
   - Project-specific observations must not be promoted directly into global rules or automatically deleted; propose an appropriate local scope or a human-reviewed disposition.
3. Propose an improvement. Prefer operations that keep the skill lean:
   - Generalize: Multiple edge cases -> one principle. Best option.
   - Replace: New principle supersedes an old one. Remove the old.
   - Compress: Same meaning, fewer words. Tighten existing prose.
   - Append: New principle not covered by existing instructions. Last resort.
   Before appending, apply the signal-to-noise check: could existing lines be removed or tightened instead? Improve what's there before adding more.
   One improvement per skill per invocation. In an explicitly requested batch, collect proposals before presenting. Preserve structural invariants.
4. Present the proposed diff, evidence, expected behavioral effect, and remaining uncertainty to the user.
5. If approved, apply the change and mark the promoted observations; do not claim model/task generalization without applicable evaluation.
6. Propose collapsing promoted entries to `Promoted YYYY-MM-DD: [topic] → [target section]`; cleanup/deletion requires explicit approval, not merely an age threshold.
7. During a requested review, assess stale notes for continued relevance; age alone does not require another workflow.
8. Re-evaluate `needs-more-data` using evidence quality and coverage. Two similar notes alone do not justify upgrading a cross-task or cross-model claim.

## Structural Invariants

These must be preserved in every edit:
- Frontmatter must contain `name` and `description`
- `## Purpose` must be the first section after the H1 title
- `## Rules` must be the last section
- Skill name in frontmatter must match the directory name
- Skill size guidance (line counts include frontmatter and blank lines):
  - No hard line limit. Brevity is still a virtue -- just not at the
    expense of precision.
  - Consider progressive disclosure when a distinct reference is only sometimes needed. Do not introduce a subagent merely to shorten or deduplicate prose.
- Ask what a rule changes and whether that change helps the user's task, safety, or necessary coordination. A line can change behavior by inducing useless work; behavioral effect alone is not evidence of value. Test proposed removals/gates across relevant task/model profiles rather than judging health by length.

## Self-Improvement

Use the same novelty, scope, and opt-out gate for self-observation. Follow Fast Loop step 5 directly; do not start another observer or automatically read this skill's own notes for an unrelated target.

## Rules

- NEVER rewrite an entire skill -- propose one targeted improvement at a time
- NEVER modify SKILL.md without user approval
- ALWAYS show the proposed diff and rationale before applying
- ALWAYS preserve structural invariants
- Ground proposals in observed failures or validated behavior cases. Distinguish hypotheses from repeated observations; two similar notes alone do not prove cross-task or cross-model benefit. Keep every SKILL.md change human-approved.
- If notes are absent or empty, say so. Use other validated evidence when available; otherwise request targeted usage data rather than inventing a justification or an observation.
