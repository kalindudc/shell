---
description: Run multi-model critic consensus on user-provided concerns
---

Load the `critique` skill and follow its instructions to analyze: $ARGUMENTS

## Concern discovery

- If concerns are provided inline in $ARGUMENTS, use them directly
- If a file path is provided, read the file for concerns
- If neither is provided, prompt the user to describe their concerns

## Rules

- ALWAYS load the `critique` skill first for detailed instructions
- ALWAYS verify source files exist before reading
- ALWAYS use actual code and tests as source material
- NEVER invent or hallucinate code behavior
- NEVER exceed 128 characters for output filename
- ALWAYS use `@skill-improver` to capture observations after skill execution completes
