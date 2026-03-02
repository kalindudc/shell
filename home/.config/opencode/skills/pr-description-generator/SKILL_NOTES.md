# Skill Notes: pr-description-generator

> Accumulated observations from real usage. Agents append entries here after skill execution.
> Run `/global/improve-skill pr-description-generator` to review and promote valuable entries into SKILL.md.
>
> ## Entry Format
>
> ```
> ### YYYY-MM-DD | <Category> | <Skill that was executing>
> **Context:** [1 sentence: what task was being performed]
> **Observation:** [1-2 sentences: what happened, what was unexpected]
> **Takeaway:** [1 sentence: actionable insight or open question]
> **Actionability:** ready-to-promote | needs-more-data | question-for-user
> ```
>
> Categories: `Edge Case` | `Successful Pattern` | `Open Question` | `Deviation` | `Tool Limitation`
>
> **Migration policy:** When migrating entries from external sources, use the original date if known. If the original date is lost, use the migration date. Never use placeholder tags like `[migrated]` in place of dates.

## Edge Cases

### 2026-03-02 | Edge Case | pr-description-generator
**Context:** Generating a PR description for a branch whose diff included changes to this skill's own SKILL_NOTES.md.
**Observation:** The diff contained both the actual PR changes and prior observation entries about the skill itself, creating a meta-situation where the description needed to describe changes to its own notes. This didn't cause confusion or errors in practice.
**Takeaway:** When a PR modifies a skill's own SKILL_NOTES.md, the generator should treat those entries as regular documentation changes rather than getting confused by self-referential content.
**Actionability:** needs-more-data

## Successful Patterns

### 2026-03-02 | Successful Pattern | pr-description-generator
**Context:** Generating a PR description for a pure docs/config PR (14 markdown files, no source code or tests).
**Observation:** The Testing subsection was omitted entirely from Technical Details, which felt correct. This confirms the earlier open question (2026-02-27) about docs-only PRs.
**Takeaway:** Omitting Testing for all-docs PRs is the right call; the earlier observation now has a second data point.
**Actionability:** ready-to-promote

### 2026-03-02 | Successful Pattern | pr-description-generator
**Context:** Same docs-only PR; the diff contained a typo (`quality.q`) in one of the changed files.
**Observation:** The skill surfaced the typo in "Notes for reviewers," making it easy for reviewers to catch an incidental issue.
**Takeaway:** PR description generators should scan diffs for incidental issues (typos, formatting errors) and surface them explicitly in reviewer notes.
**Actionability:** needs-more-data

### 2026-03-02 | Successful Pattern | pr-description-generator
**Context:** Generating a PR description for the `skill-notes-consistency` branch (21 markdown files, 253 insertions / 57 deletions).
**Observation:** A stale draft from a previous run existed at `./tmp/pr/` with multiple inaccuracies: wrong file count, wrong line counts, missing 7 files, and a fabricated "data cleanup" claim. Verification against the actual diff caught all of these.
**Takeaway:** Always verify an existing draft against the current diff -- stale drafts accumulate errors.
**Actionability:** ready-to-promote

### 2026-03-02 | Successful Pattern | pr-description-generator
**Context:** Same PR; the plan file (`tmp/plan/skill-notes-consistency-plan.md`) was available during generation.
**Observation:** The plan's research foundation and design decisions provided much richer context for the Summary's "Why" section than the commit message alone.
**Takeaway:** Plan files are the best source for the Summary's "Why" section when available.
**Actionability:** ready-to-promote

### 2026-03-02 | Successful Pattern | pr-description-generator
**Context:** Same PR; another all-docs PR with no source code or tests.
**Observation:** Testing subsection was again omitted from Technical Details, consistent with two previous observations. This is the third data point.
**Takeaway:** Third data point confirms: omit Testing for all-docs PRs.
**Actionability:** ready-to-promote

### 2026-03-02 | Successful Pattern | pr-description-generator
**Context:** Using `git_diff_summary` to analyze a 21-file docs PR for the `skill-notes-consistency` branch.
**Observation:** The tool's `category` field correctly identified all 21 files as "docs", making the "all-docs PR" determination trivial and instant — no manual file-by-file inspection needed.
**Takeaway:** The `git_diff_summary` tool's auto-categorization is the fastest way to determine PR type (docs-only, source-only, mixed); prefer it over manual inspection.
**Actionability:** ready-to-promote

## Open Questions

### 2026-02-27 | Open Question | pr-description-generator
**Context:** Generating a PR description for a pure docs/config PR (no source code, no tests).
**Observation:** The Technical details section still works well but "Testing" naturally becomes thin.
**Takeaway:** For all-docs PRs, omit the Testing section or reduce it to a one-line note.
**Actionability:** needs-more-data

## Deviations

## Tool Limitations
