---
description: Report bloat metrics and health status for all skills
agent: skill-health
---

Check the health of all skills in `~/.agents/skills/`.

If $ARGUMENTS contains a specific skill name, produce a detailed health report for that skill only with concrete compression suggestions.

Otherwise, report a concise table of all skills with:
1. Line count and approximate word count
2. Number of H2 sections and rules
3. Size tier (standard ≤200, extended 200-300, over-limit >300)
4. Health status (GREEN / YELLOW / RED)
5. SKILL_NOTES.md entry count (if present)

## Rules

- ALWAYS read actual files -- do not guess at metrics
- NEVER modify any files -- this is a read-only health check
- SKILL_NOTES.md entries are `### YYYY-MM-DD | ...` dated blocks -- NOT `## ` category headers (those are empty scaffolding). Count ONLY lines matching `^### \d{4}-\d{2}-\d{2}`
