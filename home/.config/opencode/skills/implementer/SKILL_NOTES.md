# Skill Notes: implementer

> Accumulated observations from real usage. Agents append entries here after skill execution.
> Run `/global/improve-skill implementer` to review and promote valuable entries into SKILL.md.
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

## Successful Patterns

### 2026-03-02 | Successful Pattern | implementer
**Context:** Implementing a 6-task plan for "Tiered CDN Vanity Domain Override via YAML Config" in a Ruby/Sorbet codebase (Edgey).
**Observation:** All 6 tasks completed on first attempt with zero retries. The plan's separation of "run targeted tests" (Task 5) before "run full suite" (Task 6) caught a Sorbet `T.must` type error early without waiting for the full suite. Baseline test run before starting confirmed clean state.
**Takeaway:** Plans that split targeted tests before full-suite runs catch type errors and unit failures faster; this two-stage verification pattern is worth preserving.
**Actionability:** needs-more-data

## Open Questions

## Deviations

## Tool Limitations
