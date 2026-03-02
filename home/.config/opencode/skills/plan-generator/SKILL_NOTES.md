# Skill Notes: plan-generator

> Accumulated observations from real usage. Agents append entries here after skill execution.
> Run `/global/improve-skill plan-generator` to review and promote valuable entries into SKILL.md.
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

### 2026-03-02 | Successful Pattern | plan-generator
**Context:** Planning a new skill that needed to be consistent with existing skills.
**Observation:** Reading ALL existing skills in full (not just the closest analog) provided much better consistency than just noting their existence.
**Takeaway:** The codebase exploration step should emphasize reading full content of pattern files.
**Actionability:** ready-to-promote

### 2026-03-02 | Successful Pattern | plan-generator
**Context:** Creating two related plans in a single session.
**Observation:** When the second plan depends on understanding gathered for the first, the research phase can be shared -- web research informed both plans.
**Takeaway:** Reuse research across related plans in the same session rather than re-gathering independently.
**Actionability:** needs-more-data

## Open Questions

### 2026-03-02 | Open Question | plan-generator
**Context:** Generating two plans simultaneously for related features.
**Observation:** The current approach uses independent files since they can be implemented in any order, but a plan stack in a directory might better communicate they're from the same session.
**Takeaway:** Should simultaneous plans be independent files or a plan stack directory?
**Actionability:** question-for-user

## Deviations

## Tool Limitations
