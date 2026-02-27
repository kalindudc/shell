---
description: Report bloat metrics and health status for all skills
---

Check the health of all skills in `~/.config/opencode/skills/`. For each skill:

1. Read SKILL.md and report: total lines, total words (approximate), number of H2 sections, number of rules
2. Read SKILL_NOTES.md if it exists and report: total entries, oldest entry date, any entries without timestamps
3. Flag any skill over 150 lines (the research-backed ceiling)
4. For each skill, apply the signal-to-noise heuristic: skim the content and note if sections look verbose, redundant, or like accumulated patches rather than clean principles

Present as a concise table with line counts, word counts, and a brief health assessment.

If $ARGUMENTS contains a specific skill name, report detailed health for that skill only:
read it thoroughly, identify specific lines or sections that look like noise (redundant,
overly verbose, or patch-like), and suggest concrete compression opportunities.

## Rules

- **ALWAYS** read actual files -- do not guess at metrics
- **NEVER** modify any files -- this is a read-only health check
