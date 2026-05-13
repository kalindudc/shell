# Session ID for parallel agents

`cortex update` requires `--as <id>` on every call. The recommended pattern is to **generate one session id at the start of your agent session, hold it in working memory, and reuse it** for the lifetime of that session.

## Recipe

```bash
# Once per session, hold in working memory:
SESSION_ID="${ROLE:-agent}-$(openssl rand -hex 4)"

# then on every update:
cortex update <id> -m "..." --as "$SESSION_ID"
```

Set `ROLE` to whatever role you're playing in the session — `planner`, `implementer`, `reviewer`, `triage`. Tags end up looking like `planner-7f3a9201`.

## Why "working memory" and not env / file

Two patterns that look tempting but fail in practice:

- **Environment variables (`CORTEX_AUTHOR=...`).** Sandboxed subshells throw env away. Several agent harnesses spawn sub-processes via `bash -c '...'` inside a fresh sandbox, so an exported `CORTEX_AUTHOR` set earlier in the session disappears. Worse, the failure mode is silent — the variable is just unset, and any code that reads `$CORTEX_AUTHOR` with an `or "agent"` fallback now mis-attributes every update.
- **A file in the repo (e.g. `.cortex-author`).** Two agents working in the same repo (e.g. a planner and an implementer collaborating on one branch) cannot disambiguate via a shared file — whichever wrote last wins, and the audit trail collapses into one identity. Repo files also leak across machines if committed.

The robust answer is to keep the id in the agent's own working memory: generate once, repeat on every `cortex update`. If you forget, **the CLI exits 1 with `Missing required argument: --as`** — the failure is loud and immediate, never silent.

## Tag format and id space

- **`openssl rand -hex 4`** = 8 hex chars = 4 bytes = ~4.3 billion possible suffixes. Collision risk between parallel agents on one machine is negligible.
- **Format:** `<role>-<8 hex>`. Examples: `planner-7f3a9201`, `implementer-1c0ed4a8`, `reviewer-2b88aa10`.
- **Hard limits:** max 80 chars, no newlines (validated by both the CLI and the server). The recipe stays comfortably under both.

## Spot-checking attribution

```bash
cortex show <task-id>
```

Each update line shows `[<author>]` — scan to confirm your session id appears, not `agent` or someone else's tag.
