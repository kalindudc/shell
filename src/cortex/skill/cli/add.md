# `cortex add`

Create a new task. Returns `[<id>] <title>` on success — capture the id for later `cortex update`, `cortex show`, etc.

## Usage

```bash
cortex add "<title>" [-l <lane>] [-p <priority>] [-b <body>]
```

## Args

| Flag | Alias | Default | Description |
|---|---|---|---|
| `<title>` | (positional) | — | Task title. Quote it if it contains spaces. |
| `--lane` | `-l` | `now` | Lane name. Auto-created if it doesn't exist. |
| `--priority` | `-p` | `1` | Non-negative integer. **0 = highest**, larger numbers = lower priority. |
| `--body` | `-b` | — | Longer description shown by `cortex show <id>`. |

## Example

```bash
$ cortex add "Investigate flaky CI on main" -l now -p 0 -b "Failures cluster in test/db.test.ts; happens ~1 in 5 runs."
[42] Investigate flaky CI on main
```

The new task starts in status `open` with no updates yet.

## Pitfalls

- **Author attribution is per-update, not per-task.** `cortex add` does NOT take an `--as` / `--author` flag. Tasks are created anonymously; the audit trail starts only when someone posts the first `cortex update --as <id>`. If you want to record who created the task, immediately follow `add` with an `update` carrying your session id (see [session-id recipe](../recipes/session-id.md)).
- `--priority` rejects negatives, decimals, and non-numeric strings. `-p 1.5` or `-p high` exit 1.
- A title-only task is fine; `--body` is for context the dashboard hides until you click into the task.
- Lanes are case-sensitive. `-l Now` and `-l now` create two separate lanes.
