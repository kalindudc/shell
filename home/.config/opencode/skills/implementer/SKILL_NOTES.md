# Skill Notes: implementer

> Accumulated observations from real usage. The agent appends entries here after skill execution.
> Run `/global/improve-skill implementer` to review and promote valuable entries into SKILL.md.

## Edge Cases

- **Plan naming assumptions can be wrong**: The plan assumed `name` (compiler's `@name`) was equivalent to `input.name`, but the compiler prefixes it (e.g. `"google-test"` vs `"test"`). Caught by running tests after Task 1 -- always verify naming logic with a test run before continuing.
- **Integration tests with prefix matching**: When adding a new resource variant with a prefix that's a superstring of an existing prefix (e.g. `tiered_origin_ip_` vs `tiered_origin_`), integration tests using `start_with?` will match both. Need to update integration tests to strip the more specific prefix first.
- **Return type widening when mixing Resources and Datasources**: When a method returns both `Terraformable::Resource` and `Terraformable::Datasource`, the return type must be `T::Array[Output::Terraformable]` (the common ancestor), not `T::Array[Output::Terraformable::Resource]`. Sorbet typechecker caught no errors here because the outer `file <<` accepts `Output::Resource` (the root), but it's worth checking the class hierarchy early.

## Successful Patterns

- **User-driven simplification mid-implementation**: The user requested three meaningful simplifications during implementation: (1) keep prefix helper alongside full-name helper instead of replacing, (2) IPv4-only instead of IPv4+IPv6, (3) single symbol parameter instead of two booleans. Each reduced complexity. The implementer skill should emphasize pausing for user input at design decision points rather than committing to the plan's approach when alternatives exist.
- **Bottom-up implementation order for parameter threading**: When refactoring a parameter through a call chain (e.g. `tiered_routing` symbol), updating the leaf method first (`backend_service_name_for_route`), then middle helpers, then entry points produces fewer intermediate broken states.
- **Running focused tests after each task**: Running only the relevant test file after each task (not the full suite) gives fast feedback. Save the full suite for the final verification pass.

## Open Questions

- Should the implementer skill have explicit guidance for when users request plan deviations mid-implementation? Currently it says "NEVER deviate from the plan without user approval" but doesn't describe how to handle user-initiated deviations (which are pre-approved by definition). A note about updating the plan inline with deviation markers would help.
- **Post-implementation bugs as continuation**: When a user discovers a bug after the main plan is "complete", the implementer should treat it as a continuation (write failing test first, then fix) rather than requiring a new plan. The debugger skill's "reproduce first" principle applies naturally here -- the failing test IS the reproduction.
