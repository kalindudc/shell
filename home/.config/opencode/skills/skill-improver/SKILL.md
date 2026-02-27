---
name: skill-improver
description: Review a skill's accumulated observations and propose targeted improvements
---

# Skill Improver Skill

## Purpose

Review a skill's usage observations and propose targeted improvements. You read SKILL.md and SKILL_NOTES.md for a given skill, identify patterns, and produce a minimal diff that makes the skill better.

You are the slow feedback loop. The agent appends notes during use (fast loop). You review those notes and propose changes to the core skill (slow loop). The human gates every change.

## Approach

1. Read the target skill's SKILL.md and SKILL_NOTES.md
2. Identify patterns in the notes:
   - Recurring edge cases -> should become instructions in SKILL.md
   - Successful patterns -> should become recommended approaches
   - Open questions -> may need user input before becoming instructions
3. Propose a specific, minimal change to SKILL.md
   - One improvement per invocation -- do not rewrite the whole skill
   - If SKILL.md is approaching 150 lines, simplify existing content to make room
   - Preserve structural invariants: frontmatter, ## Purpose first, ## Rules last
4. Present the proposed diff to the user with rationale
5. If approved, apply the change and mark promoted notes in SKILL_NOTES.md
6. Review notes older than 90 days -- suggest promotion or removal

## Structural Invariants

These must be preserved in every edit:
- Frontmatter must contain `name` and `description`
- `## Purpose` must be the first section after the H1 title
- `## Rules` must be the last section
- Skill name in frontmatter must match the directory name
- SKILL.md should stay under 150 lines

## Rules

- NEVER rewrite an entire skill -- propose one targeted improvement at a time
- NEVER modify SKILL.md without user approval
- ALWAYS show the proposed diff and rationale before applying
- ALWAYS preserve structural invariants
- ALWAYS check that the improvement addresses a real pattern from SKILL_NOTES.md, not a hypothetical
- If SKILL_NOTES.md does not exist or is empty, tell the user the skill needs more usage data before it can be improved
