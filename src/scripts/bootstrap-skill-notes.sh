#!/usr/bin/env bash

# Bootstrap SKILL_NOTES.md files for all OpenCode skills.
# SKILL_NOTES.md is gitignored (it contains local observations),
# so this script creates the template for each skill directory
# that has a SKILL.md but no SKILL_NOTES.md.

set -o errexit
set -o nounset
set -o pipefail

SKILLS_DIR="${1:-${HOME}/.config/opencode/skills}"

if [[ ! -d "${SKILLS_DIR}" ]]; then
  echo "Skills directory not found: ${SKILLS_DIR}"
  exit 0
fi

for skill_dir in "${SKILLS_DIR}"/*/; do
  [[ -d "${skill_dir}" ]] || continue
  [[ -f "${skill_dir}/SKILL.md" ]] || continue

  notes_file="${skill_dir}/SKILL_NOTES.md"
  skill_name="$(basename "${skill_dir}")"

  if [[ -f "${notes_file}" ]]; then
    continue
  fi

  cat > "${notes_file}" <<EOF
# Skill Notes: ${skill_name}

> Accumulated observations from real usage. Agents append entries here after skill execution.
> Run \`/global/improve-skill ${skill_name}\` to review and promote valuable entries into SKILL.md.
>
> ## Entry Format
>
> \`\`\`
> ### YYYY-MM-DD | <Category> | <Skill that was executing>
> **Context:** [1 sentence: what task was being performed]
> **Observation:** [1-2 sentences: what happened, what was unexpected]
> **Takeaway:** [1 sentence: actionable insight or open question]
> **Actionability:** ready-to-promote | needs-more-data | question-for-user
> \`\`\`
>
> Categories: \`Edge Case\` | \`Successful Pattern\` | \`Open Question\` | \`Deviation\` | \`Tool Limitation\`

## Edge Cases

## Successful Patterns

## Open Questions

## Deviations

## Tool Limitations
EOF

  echo "Created ${notes_file}"
done
