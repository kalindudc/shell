---
description: Collect contributions and generate an impact-focused performance review for a given period
---

Load the `performance-review` skill and follow its instructions to generate a performance review.

Period and additional context from the user: $ARGUMENTS

If no time period is specified in the arguments, prompt the user for the review period (e.g., "last 6 months", "2025 H2", "Q4 2025").

## Rules

- **ALWAYS** load the `performance-review` skill first for detailed instructions
- **NEVER** fabricate or embellish contributions -- every claim must trace to real data
- **ALWAYS** verify GitHub authentication before collecting data
- **ALWAYS** use `@skill-improver` to capture observations after skill execution completes
