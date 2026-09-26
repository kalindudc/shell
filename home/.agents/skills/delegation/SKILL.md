---
name: delegation
description: Strategy for delegating substantial work to minions when independent subtasks or context isolation justify the overhead.
---

# Delegation

## Activation and Reuse

Use this skill for substantial work where independent subtasks or context isolation justify delegation. Do not load it merely because a session began or a task has multiple steps. Direct replies and bounded work need no automatic delegation setup.

Reuse guidance already in context; reload only if it has changed or is no longer in context.

## When to Spawn

Use `spawn` when substantial independent work or context isolation has a concrete benefit:
- Independent questions can be answered without shared writes or data dependencies.
- A bounded investigation benefits from a focused context rather than duplicating evidence already available to the parent.
- A complex subtask can return a useful, verifiable result that supports the next decision.

Use only registered delegation capabilities. In Pi, `spawn` is foreground with a nonempty `tasks` array; one call can run independent tasks in parallel and returns when they finish. Do not invent a background tool or promise that the parent can continue while the foreground call is blocked.

Task-array template (replace placeholders with verified paths and concrete questions):

```json
{"tasks":[{"task":"In <repo>/module-a, verify <claim A> against source and tests without edits; return findings with file:line evidence and uncertainty."},{"task":"In <repo>/module-b, verify independent <claim B> against source and tests without edits; return findings with file:line evidence and uncertainty."}]}
```

Per-task `model` fields select each minion's model (see Model Selection).

## When NOT to Spawn

- Single command, single edit, or single file read
- You need the output in the same thought to make a decision
- User is interactively iterating and wants tight feedback loops
- Overhead exceeds benefit (trivial tasks)

## Common Patterns

- Plan execution: delegate independent scopes with disjoint file ownership; the parent verifies integration.
- Research/review: group related questions and evidence, rather than creating a child for each small claim.
- Verification: run a simple check inline; delegate only when isolation or substantial independent work justifies the coordination cost.
- Multi-file edits: batch related files under one owner and wait for dependent results before continuing.

## Model Selection

 Skills sync across machines that may have different providers — on any machine where you have not validated the table, discover the local catalog first with the script shipped next to this skill:

    python3 ~/.agents/skills/delegation/discover-models.py

It prints every usable model (authenticated providers only) with per-M cost, context window, and reasoning/image flags: this machine's `enabledModels` picks lead the first page, followed by the cheapest of the curated families (glm, gpt, claude, deepseek, grok, gemini, solar). Slices: `--limit N`, `--min-out <usd>` (e.g. `--min-out 2` shows premium tiers only), `--provider <key>` (a store provider key like `openrouter`, NOT an id prefix like `gemini`), `--all` (full catalog — use when the curated families are absent on this machine).

Map the table's ROLES onto the script's output — the roles transfer across machines, the concrete ids do not:

- DEFAULT — cheapest fast generalist with reasoning + image input (`glm-5.3-flash`)
- BUDGET STEP-UP — next-cheapest strong generalist (here: `deepseek-v4.1-flash`)
- MID — mid-priced strong reasoning (here: `gemini-3.8-flash`)
- PREMIUM — strongest reasoning at moderate cost (here: `gpt-5.6-sol`, `kimi-coding/k3`)
- FLAGSHIP — last resort (here: `claude-opus-5.5`)
- FREE — zero-cost large-context models for bulk low-stakes sweeps (here: `nemotron-3-ultra-550b-a55b:free`)

On machines that DO have this table's providers, the default is `glm-5.3-flash` — $0.045/M input, $0.14/M output, 1M context, text+image, reasoning. A typical minion run costs under $0.001.

### Lookup table (verified 2026-09-26, this machine)

Pick the first row that matches the task. When output quality is insufficient, escalate one row at a time.

| Task | Model | Notes |
|---|---|---|
| Most delegation: verification sweeps, bounded research, summarization, mechanical edits, file exploration, test runs | `glm-5.3-flash` | $0.045/$0.14, 1M ctx, text+image |
| Flash output weak but task still mechanical: larger refactors, longer synthesis | `deepseek-v4.1-flash` | $0.15/$0.6, 1M ctx, text+image |
| Bug diagnosis, module-level code review, bounded debugging, doc-heavy analysis | `gemini-3.8-flash` | $0.75/$3.75, 1M ctx, text+image |
| Hard reasoning: algorithms, security review, concurrency, subtle root-causing | `gpt-5.6-sol` | $2/$10, 1.05M ctx, text+image |
| Hard reasoning, strongest coding model | `kimi-coding/k3` | $3/$15 catalog rates in session costs (actual plan billing may differ); 1M ctx, text+image |
| High-stakes subtask where cheaper tiers already failed | `claude-opus-5.5` | $4/$20, 1M ctx, text+image; last resort |
| Bulk low-stakes sweeps: bulk classification, extraction, triage at scale | `nemotron-3-ultra-550b-a55b:free` | $0, 1M ctx; variable quality, rate-limited |

### Applying the table

- The table names models by short, provider-agnostic id for readability. When spawning, ALWAYS pass the full `provider/id` exactly as the discovery script prints it (e.g. `openrouter/z-ai/glm-5.3-flash`, not `glm-5.3-flash`) — the minion resolver matches `provider/id` or exact catalog ids, not short names. If the table's model is absent on this machine, run the discovery script and pick the full id of the model filling the same role.
- Set `model` per task entry, e.g. `"model": "kimi-coding/k3"`. Works in batch mode — every task entry can carry its own model, so mixed-tier batches are one call.
- Unknown models, ambiguous ids, or models without configured auth fail that minion immediately with a clear error; the rest of the batch proceeds.
- Never start at flagship. Premium rows cost roughly 50-100x the default per minion; escalate only failures, never preemptively.

Maintenance: picks and prices verified 2026-09-26 on this machine from the local catalog (`~/.pi/agent/models-store.json`) and `enabledModels` in settings; k3 session-cost billing at catalog rates confirmed 2026-09-26 (earlier $0 plan-billed observation applied to the retired kimi-k2 model). Per-task model resolution added to pi-minions the same day (verify after extension upgrades that `model` fields still apply). `discover-models.py` needs no maintenance — it reads whatever catalog/auth exist on the current machine. Refresh the table when notable models release, and re-verify it on any machine where it is used.

## Task Descriptions

Every minion task MUST include:
- WHAT to do — specific and concrete
- WHERE — file paths, directories, URLs
- HOW to verify — test commands, expected outputs
- WHAT to return — summary of results, not raw output
