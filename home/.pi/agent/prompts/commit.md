---
description: Generate a concise, high-quality git commit message for the current branch.
---

Generate a concise, high-quality git commit message for review and create a commit new changes

## Context to evaluate:
- All commits in this branch not yet merged into main
- Staged changes (git diff --cached)
- Unstaged changes (git diff)

## Protocol
- Infer the primary intent of the changes (feat, chore, docs, test, breaking change)
- Avoid repeating prior commit messages; summarize net-new value
- Be specific about *what* changed and *why*, not implementation minutiae
- Prefer conventional commit style if applicable
- Use the template for the commit message
- Preset the commit message to the user for review
- If approved, stage the changes and commit with the commit message

## Template
```
[title line]

- [bullet point]
- ...
```

## Rules:
- ALWAYS add a first line: a single, concise title (≤ 72 chars, imperative mood)
- Then OPTIONAL bullets (max 6):
  - Each bullet is exactly one sentence
  - Each captures a distinct meaningful change or rationale
  - No trailing punctuation clutter, no redundancy
- ALWAYS use lowercase letters, the only exception is for acronyms (eg. UI / UX, DOM)
- NEVER File lists, diffs, or code
- NEVER use generic filler like "updates" or "misc changes"
- NEVER push a commit to upstream
- NEVER rebase or overwrite commits
