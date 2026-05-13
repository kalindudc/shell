# `cortex serve`

Run the cortex API server and browser dashboard as a localhost-only daemon. The daemon writes its pid and URL under the cortex config dir so the CLI can talk to it; both the JSON API and the dashboard are served from the same port.

## Usage

```bash
cortex serve [-p <port>] [--foreground] [--no-open]
```

## Args

| Flag | Alias | Default | Description |
|---|---|---|---|
| `--port` | `-p` | `7777` | TCP port on `127.0.0.1`. Use `0` to pick a free port. |
| `--foreground` | — | `false` | Run attached to the current shell (Ctrl+C to stop) instead of detaching. |
| `--no-open` | — | `false` | Do not auto-open the dashboard in a browser (set this on headless machines). |

## Example

```bash
$ cortex serve
✓ cortex serving at http://127.0.0.1:7777 (pid 41218)
```

The URL is also written to `~/.config/cortex/cortex.url` and the pid to `~/.config/cortex/cortex.pid`. Open the URL in any browser to see the dashboard. Subsequent CLI calls (`cortex add`, `cortex update`, ...) automatically route through the daemon.

## Stopping the daemon

- **Foreground:** Ctrl+C. The `SIGINT`/`SIGTERM` handler closes the DB and removes the pid/url files.
- **Detached:** `cortex stop` if available, otherwise `kill $(cat ~/.config/cortex/cortex.pid)`.
- **`cortex reset`** also stops the daemon as part of its cleanup before wiping the DB.

## Pitfalls

- **Localhost-only bind is the security boundary. There are no bearer tokens.** The server binds to `127.0.0.1` and refuses non-loopback connections. Do not put cortex behind a reverse proxy, an SSH `-L` tunnel that exposes it elsewhere, or `socat` to a public interface — anyone reaching the port has full CRUD on every task.
- If port `7777` is taken, `serve` fails fast. Re-run with `-p 0` to auto-pick or `-p <other>`. Update bookmarks accordingly — the CLI follows the URL file automatically, but your browser tab does not.
- Running two `cortex serve` instances against the same DB is unsupported. The pid file is overwritten and the older daemon will keep running but won't be reachable via the CLI. Stop the old one first.
- Browser notifications require the dashboard tab to be open and notification permission granted. The notification fires only on transitions into `blocked` status (not on `done`, not on routine updates).
