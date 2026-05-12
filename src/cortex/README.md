# cortex

Personal task tracker for engineers supervising parallel AI coding agents.
Single self-contained binary at `home/bin/cortex` with a complete CLI, REST + SSE
API on `127.0.0.1`, and a SQLite WAL store at `~/.config/cortex/cortex.db`.

## Quick start

```bash
task cortex:build          # compile to home/bin/cortex
cortex init                # create ~/.config/cortex/cortex.db
cortex add "ship plan 1" -p 0
cortex ls
cortex serve               # start API daemon on 127.0.0.1:7777
cortex stop                # stop the daemon
```

For development without compiling:

```bash
task cortex:dev -- ls --json
```

## Commands

| Command | Purpose |
| --- | --- |
| `init` | initialize the SQLite database |
| `add <title> [-l lane] [-p int] [-b body]` | create a task (auto-creates `lane` if missing) |
| `ls [-l lane] [-s status] [--json]` | list tasks, grouped by lane, sorted by priority (`s` = `open\|review\|blocked\|done`) |
| `show <id> [--json]` | show one task with its updates |
| `update <id> -m <msg> [-s status] [-b body]` | post an update; `status` = `open\|review\|blocked\|done` |
| `edit <id> [-t title] [-b body] [-p int]` | edit task fields |
| `mv <id> <lane>` | move a task to another lane (auto-creates `lane` if missing) |
| `rm <id> [-f]` | remove a task (prompts unless `-f`) |
| `lane add\|ls\|edit\|rm` | manage lanes |
| `serve [-p port] [--foreground]` | run the HTTP daemon |
| `reset` | stop the daemon (if running), wipe the DB + WAL sidecars + pid/url files, then re-init an empty DB. Requires typing `RESET` to confirm. |
| `stop` | stop the running daemon |

## Lanes

Lanes are flat strings (`now`, `later`, `blocked`, anything you want). `now`
is seeded automatically and cannot be removed. Any lane referenced by `cortex
add -l <name>` or `cortex mv <id> <name>` is created on the fly with defaults
(no color, WIP limit 3). Use `cortex lane add <name> -c <color> -w <limit>`
upfront when you want to set those explicitly, and `cortex lane ls` to inspect.

## Priority

Priority is a non-negative integer where **0 is the highest priority**. There
is no upper bound — use whatever scale fits (`0/1/2`, `0..10`, etc.). Tasks
are listed by priority ascending, ties broken by oldest-created first.

```
cortex add "ship the thing" -p 0      # top of the list
cortex add "normal work"              # default priority = 1
cortex add "someday" -p 9             # bottom
cortex edit 42 -p 0                   # promote a task
```

For every flag that takes a fixed enum (`--status`, `--severity`), `cortex
<command> --help` shows the exact set of allowed values inline.

## Storage

- **DB file:** `~/.config/cortex/cortex.db` (XDG-aware via `$XDG_CONFIG_HOME`).
- **Override for tests:** `CORTEX_DB=/path/to/db cortex …`.
- **Mode:** SQLite WAL with `PRAGMA foreign_keys = ON`. The `-wal` and `-shm`
  sidecar files are normal and persistent.
- **PID file:** `~/.config/cortex/cortex.pid` while `cortex serve` runs.

## API surface

Bound to `127.0.0.1` only. No auth in Plan 1.

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/` | placeholder text (Plan 2 ships the UI) |
| GET | `/api/health` | `{ ok: true, version }` |
| GET | `/api/tasks?lane&status` | list tasks |
| POST | `/api/tasks` | create a task |
| GET | `/api/tasks/:id` | fetch one task |
| PATCH | `/api/tasks/:id` | edit title/body/priority |
| PATCH | `/api/tasks/:id/status` | change status |
| PATCH | `/api/tasks/:id/lane` | move lane |
| DELETE | `/api/tasks/:id` | remove a task |
| GET | `/api/tasks/:id/updates` | list updates for a task |
| POST | `/api/tasks/:id/updates` | post an update |
| GET | `/api/lanes` | list lanes |
| POST | `/api/lanes` | create a lane |
| PATCH | `/api/lanes/:name` | edit a lane (`rename` cascades to tasks) |
| DELETE | `/api/lanes/:name` | remove an empty lane (refuses `now`) |
| GET | `/events` | SSE stream of `task.added`, `task.updated`, `task.removed`, `update.posted`, `lane.changed` |

SSE clients receive a `heartbeat` event every 15 s.

