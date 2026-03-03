---
name: skill-improver
description: Review a skill's accumulated observations and propose targeted improvements
---

# Skill Improver Skill

## Purpose

Review a skill's usage observations and propose targeted improvements. You read SKILL.md and SKILL_NOTES.md for a given skill, identify patterns, and produce a minimal diff that makes the skill better.

You are the slow feedback loop. Agents append notes during use (fast loop). You review and propose changes (slow loop). The human gates every change.

## Approach

1. Read the target skill's SKILL.md and SKILL_NOTES.md
   - Entries in SKILL_NOTES.md follow a structured format (date, category, context, observation, takeaway, actionability). Use the actionability field to prioritize: "ready-to-promote" entries are candidates for improvement. "needs-more-data" entries need more occurrences. "question-for-user" entries should be surfaced to the user before acting.
2. Identify patterns in the notes:
   - Recurring edge cases -> should become instructions in SKILL.md
   - Successful patterns -> should become recommended approaches
   - Open questions -> may need user input before becoming instructions
   - Project-specific or single-codebase observations -> remove (they can never generalize into skill instructions)
3. Propose an improvement. Prefer operations that keep the skill lean:
   - **Generalize**: Multiple edge cases → one principle. Best option.
   - **Replace**: New principle supersedes an old one. Remove the old.
   - **Compress**: Same meaning, fewer words. Tighten existing prose.
   - **Append**: New principle not covered by existing instructions. Last resort.
   Before appending, apply the signal-to-noise check: could existing lines be removed or tightened instead? Improve what's there before adding more.
   One improvement per invocation. Preserve structural invariants.
4. Present the proposed diff to the user with rationale
5. If approved, apply the change and mark promoted notes in SKILL_NOTES.md
6. Clean up promoted entries older than 7 days -- remove them from SKILL_NOTES.md (their insight already lives in SKILL.md)
7. Review notes older than 90 days -- suggest promotion or removal

## Structural Invariants

These must be preserved in every edit:
- Frontmatter must contain `name` and `description`
- `## Purpose` must be the first section after the H1 title
- `## Rules` must be the last section
- Skill name in frontmatter must match the directory name
- No skill should exceed 150 lines -- research shows instruction-following
  degrades past ~200 lines, and 150 gives margin. But size alone doesn't
  determine health. Apply the signal-to-noise check: "If I removed this
  line, would the agent behave differently?" If no, the line is noise
  regardless of total size. A 140-line skill with zero noise is healthier
  than a 60-line skill with half noise.

## Self-Improvement

After execution, use `@skill-improver` to capture observations about this skill's performance. Before execution, check `SKILL_NOTES.md` for known edge cases.

## Rules

- NEVER rewrite an entire skill -- propose one targeted improvement at a time
- NEVER modify SKILL.md without user approval
- ALWAYS show the proposed diff and rationale before applying
- ALWAYS preserve structural invariants
- ALWAYS check that the improvement addresses a real pattern from SKILL_NOTES.md, not a hypothetical
- If SKILL_NOTES.md does not exist or is empty, tell the user the skill needs more usage data before it can be improved
