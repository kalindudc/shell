# Delegation: who gets which job, and how to brief it

Read this before you spawn a member. It covers when to delegate, which model a member runs on, and what every task message carries. `briefs.md` has the full brief templates.

## When to delegate

- Delegate work that is substantial, can run in parallel, or needs its own context: a research question with many sources, a build in its own worktree, a review that must be independent.
- Do it yourself when it's a single command, edit or read, when you need the answer in the same thought to decide, or when briefing would cost more than the work.
- Group related questions under one member instead of one member per small claim. Split a broad sweep into focused members, because a member with too much to cover runs out of turns and returns progress instead of findings.
- Give parallel members disjoint files, and integrate their results yourself (`SKILL.md`, Members).

## Choose the model on every task

A member with no model set usually runs on the lead's own model, often the most expensive one in the session. Set a persona or a model on every task, and record your choices in `RULES.md` so the whole fleet uses them.

| Work | Model |
|---|---|
| Implementation from a clear brief: planned features, fixes, refactors, test runs | a strong coding model, about half the flagship's price |
| Read-only research: code questions, docs, web, inventories | a cheaper, fast model |
| Design calls, high-risk or high-impact changes, writing for the human | the lead's own model |
| Verifying another member's result | a different model family from the producer, at least as strong |
| Critics | three model families (`critique.md`) |
| Permanent watchers that only judge relevance | the cheapest model that can do it |

- Leave the model unset only for work that needs the lead's judgment, and say why in the task.
- If a cheaper model's result isn't good enough, rerun it once on the lead's model rather than trying several models.
- Never move a reviewer, verifier or critic to a cheaper model to save cost.
- If the models you expect aren't available, list the ones your harness offers and pick the nearest equivalent. `bare-harness.md` names each bare harness's models.

## Every task message carries

1. What to do, specifically.
2. Where: file paths, directories, URLs and revisions.
3. How to verify it: the test command and the expected output.
4. What to return: a summary with evidence, not raw output.

For research, also give numbered questions, a tool-call budget (for example "about 15 tool calls") and explicit non-scope (for example "no full-file review").

## Cleanup

Archive a member once its final answer is read and nothing will go back to it. Keep one you will return to, such as a builder waiting on review rounds, and archive it when that loop ends (`SKILL.md`, Hygiene).
