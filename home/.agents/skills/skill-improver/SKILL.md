---
name: skill-improver
description: Review a skill's accumulated observations and propose targeted improvements
---

# Skill Improver Skill

## Purpose

Review a skill's usage observations and propose targeted improvements. You read SKILL.md and SKILL_NOTES.md for a given skill, identify patterns, and produce a minimal diff that makes the skill better.

You are the slow feedback loop. Agents append notes during use (fast loop). You review and propose changes (slow loop). The human gates every change.

## Opt-Out

If the environment variable `SKIP_SKILL_NOTES=1` is set, skip all skill-improver operations (both fast loop and slow loop). Return immediately without reading or writing SKILL_NOTES.md. This allows disabling the observation pipeline entirely when it is not wanted.

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

1. Pre-check: Read the target skill's SKILL.md. If the observation restates an existing instruction, do not append.
2. Deduplicate: Read SKILL_NOTES.md. If a promoted entry already captures this insight, do not append.
3. Batch per session: If multiple observations come from the same task, write ONE entry with multiple bullets under Observation/Takeaway -- not separate entries.
4. Tag honestly: Use `needs-more-data` only for genuinely novel observations with <2 data points. If 2+ entries already exist for the same pattern, tag `ready-to-promote`.
5. Self-observation: When observing the skill-improver itself, append directly to `skill-improver/SKILL_NOTES.md` -- do not invoke `@skill-improver` recursively.

## Slow Loop (Reviewing Notes)

1. Read the target skill's SKILL.md and SKILL_NOTES.md. Prioritize by actionability: `ready-to-promote` first, then `question-for-user` (surface to user), then `needs-more-data`.
2. Identify patterns in the notes:
   - Recurring edge cases -> should become instructions in SKILL.md
   - Successful patterns -> should become recommended approaches
   - Open questions -> may need user input before becoming instructions
   - Project-specific or single-codebase observations -> remove (they can never generalize into skill instructions)
3. Propose an improvement. Prefer operations that keep the skill lean:
   - Generalize: Multiple edge cases -> one principle. Best option.
   - Replace: New principle supersedes an old one. Remove the old.
   - Compress: Same meaning, fewer words. Tighten existing prose.
   - Append: New principle not covered by existing instructions. Last resort.
   Before appending, apply the signal-to-noise check: could existing lines be removed or tightened instead? Improve what's there before adding more.
   One improvement per skill per invocation. In batch mode (no specific skill), collect all proposals before presenting. Preserve structural invariants.
4. Present the proposed diff to the user with rationale
5. If approved, apply the change and mark promoted notes in SKILL_NOTES.md
6. Collapse promoted entries to: `Promoted YYYY-MM-DD: [topic] → [target section]`. Delete fully after 7 days.
7. Review notes older than 90 days -- suggest promotion or removal
8. Re-evaluate stale `needs-more-data`: if 2+ entries exist for the same pattern, upgrade to `ready-to-promote`

## Structural Invariants

These must be preserved in every edit:
- Frontmatter must contain `name` and `description`
- `## Purpose` must be the first section after the H1 title
- `## Rules` must be the last section
- Skill name in frontmatter must match the directory name
- Skill size guidance (line counts include frontmatter and blank lines):
  - No hard line limit. Brevity is still a virtue -- just not at the
    expense of precision.
  - Over 300 lines: Should be decomposed (e.g., split review criteria
    into subagent prompts) unless the complexity genuinely requires it.
- Regardless of tier, apply the signal-to-noise check: "If I removed this
  line, would the agent behave differently?" If no, the line is noise.
  A 140-line skill with zero noise is healthier than a 60-line skill
  with half noise.

## Self-Improvement

Before execution, check `SKILL_NOTES.md` for known edge cases. For self-observation, see Fast Loop step 5 — append directly, do not recurse.

## Rules

- NEVER rewrite an entire skill -- propose one targeted improvement at a time
- NEVER modify SKILL.md without user approval
- ALWAYS show the proposed diff and rationale before applying
- ALWAYS preserve structural invariants
- ALWAYS check that the improvement addresses a real pattern from SKILL_NOTES.md, not a hypothetical
- If SKILL_NOTES.md does not exist or is empty, tell the user the skill needs more usage data before it can be improved
