---
description: Evaluate concerns through multi-model critic consensus
---

Load the `critique` skill and follow its instructions to evaluate: $ARGUMENTS

If no concerns are provided, prompt the user for concerns to evaluate.

## Rules

- ALWAYS load the `critique` skill first for detailed instructions
- ALWAYS verify source files exist before reading
- ALWAYS use actual code and tests as source material
- NEVER invent or hallucinate code behavior
- NEVER exceed 128 characters for output filename
- ALWAYS use `skill-improver` agent to capture observations after skill execution completes, NEVER add any manual notes
