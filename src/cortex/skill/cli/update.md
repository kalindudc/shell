# `cortex update`

Post an update on a task. Optionally flip the task's status in the same call.

> ⚠️ **`--as <id>` (alias `--author`) IS REQUIRED ON EVERY CALL.**
>
> Cortex is multi-agent by design. Every update must self-attribute so the human supervisor can tell the planner from the implementer from the reviewer in the inbox. There is no default, no env-var fallback, and no per-repo config. Generate a session id ONCE at the start of your agent session via the [session-id recipe](../recipes/session-id.md) and pass it on every `cortex update`.
>
> If `--as` is missing, [citty](https://github.com/unjs/citty) rejects the call at parse time, before the daemon is even contacted. You will see something like:
>
> ```text
> $ cortex update 42 -m "looks ready"
> Missing required argument: --as
> ```
>
> Exit code is non-zero. **This is loud, not silent — easy to catch in agent loops.**

## Usage

```bash
cortex update <id> -m "<message>" --as <session-id> [-s <status>] [-b <body>]
```

## Args

| Flag | Alias | Required | Description |
|---|---|---|---|
| `<id>` | (positional) | yes | Task id from `cortex ls`. |
| `--message` | `-m` | yes | Short summary, **max 1024 chars**. No newlines. |
| `--as` | `--author` | **REQUIRED** | Session-id author tag. Format: `<role>-<8 hex>`, max 80 chars, no newlines. See [recipes/session-id.md](../recipes/session-id.md). |
| `--status` | `-s` | no | One of `open`, `review`, `blocked`, `done`. Flips the task and writes an audit-trail row. |
| `--body` | `-b` | no | Longer detail shown by `cortex show <id>`. |

## Examples

Plain update, no status change:

```bash
cortex update 42 -m "Repro confirmed — race in test setup, not the code under test." \
  --as planner-7f3a9201
```

Update + status flip (writes BOTH a message row AND a `status → blocked` audit row, both attributed to `--as`):

```bash
cortex update 42 -m "Need a Stripe test key from ops; pausing here." \
  -s blocked \
  --as implementer-1c0ed4a8
```

The dashboard fires a browser notification ONLY for the second example, because the transition is into `blocked`.

## Pitfalls

- **Forgetting `--as` exits 1** with `Missing required argument: --as`. The fix is to grab your session id (held in working memory for the lifetime of the session — see the recipe) and re-run.
- **Newlines in `-m` or `--as` are rejected.** Keep updates one-line and prose-y; use `-b` for multi-line context.
- **`--as` over 80 chars is rejected.** The format is `<role>-<8 hex>` (~17 chars); 80 is generous but enforced.
- **`-m` over 1024 chars is rejected** by both the CLI validator and the SQLite `CHECK` constraint. If your update is that long, the body (`-b`) is the right place; keep `-m` as a scannable headline.
- **No `--severity` flag exists.** Encode urgency in the message text (`"ready for review"`, `"blocking release"`, `"FYI only"`). Structured signal goes in `--status`, not a separate severity dimension.
- Setting `-s` to the task's CURRENT status still writes an audit row. That's intentional: re-confirming `blocked` after a check-in is useful history.
