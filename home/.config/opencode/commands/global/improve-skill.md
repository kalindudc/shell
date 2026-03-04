---
description: Review and improve a skill based on accumulated usage observations
---

Load the `skill-improver` skill and follow its instructions to improve: $ARGUMENTS

If no skill name is provided, run in **batch mode**:
1. Scan ALL skills under `~/.config/opencode/skills/` that have SKILL_NOTES.md with entries
2. For each skill, run the slow loop silently — collect all proposed changes (promotions, cleanups, removals) without prompting
3. Group proposals by type: promotions, cleanups (collapse/delete promoted entries), removals (stale/project-specific)
4. Present the full batch to the user as a numbered list with skill name, change type, and one-line summary
5. The user accepts, rejects, or modifies each item — then apply all accepted changes in one pass

## Rules

- **ALWAYS** load the `skill-improver` skill first for detailed instructions
- Follow the skill's Rules section — do not duplicate them here
- In batch mode, collect ALL proposals before prompting — never interrupt the scan to ask about individual changes
