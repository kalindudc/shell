---
description: Creates a structured PR description for the current branch
---

Load the `pr-description-generator` skill and follow its instructions to generate a PR description for the current branch.

Additional context from the user: $ARGUMENTS

## Rules

- **ALWAYS** load the `pr-description-generator` skill first for detailed instructions
- **ALWAYS** verify source files exist before reading
- **ALWAYS** use actual code and tests as source material
- **NEVER** invent or hallucinate code behavior
- **NEVER** exceed 128 characters for output filename