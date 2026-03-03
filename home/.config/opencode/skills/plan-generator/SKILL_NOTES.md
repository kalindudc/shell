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

### 2026-03-02 | Edge Case | plan-generator
**Context:** Researching design options for a tiered CDN vanity domain feature.
**Observation:** Initial design options missed a critical data dimension -- generated DNS names are per (edge, backend) pair, not per backend alone. The user caught the error; multiple rounds of scope clarification were needed before the plan was correct.
**Takeaway:** When a feature involves generated/derived names, always trace the full parameter space of the naming function (e.g. `fqdn(edge, backend)`) to understand cardinality before proposing config structures.
**Actionability:** ready-to-promote

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

### 2026-03-02 | Successful Pattern | plan-generator
**Context:** After writing a plan for tiered CDN vanity domains, the user requested a concrete table of all generated DNS names.
**Observation:** Producing a table of (edge, backend, generated_name, proposed_vanity) required tracing through config files, .edge files, and compiler defaults -- but was highly valuable for the user to create external DNS records.
**Takeaway:** For plans involving DNS/naming changes, always produce a concrete table of all affected names as a deliverable alongside the plan.
**Actionability:** ready-to-promote

## Open Questions

### 2026-03-02 | Open Question | plan-generator
**Context:** Generating two plans simultaneously for related features.
**Observation:** The current approach uses independent files since they can be implemented in any order, but a plan stack in a directory might better communicate they're from the same session.
**Takeaway:** Should simultaneous plans be independent files or a plan stack directory?
**Actionability:** question-for-user

## Deviations

## Tool Limitations
