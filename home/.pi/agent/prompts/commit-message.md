---
description: Generate a concise, high-quality git commit message for the current branch.
---

Generate a concise, high-quality git commit message for the current branch.

Context to evaluate:
- All commits in this branch not yet merged into main
- Staged changes (git diff --cached)
- Unstaged changes (git diff)

Instructions:
- Infer the primary intent of the changes (feat, chore, docs, test, breaking change)
- Avoid repeating prior commit messages; summarize net-new value
- Be specific about *what* changed and *why*, not implementation minutiae
- Prefer conventional commit style if applicable

Output format:
- First line: a single, concise title (≤ 72 chars, imperative mood)
- Then OPTIONAL bullets (max 6):
  - Each bullet is exactly one sentence
  - Each captures a distinct meaningful change or rationale
  - No trailing punctuation clutter, no redundancy

Do not include:
- File lists, diffs, or code
- Generic filler like "updates" or "misc changes"

Return only the commit message.
