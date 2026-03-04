# OpenCode Plugins

Custom plugins for [OpenCode](https://opencode.ai). Each plugin is a single `.ts` file exporting a `Plugin` function, with tests in `test/`.

```
plugins/
  session-recorder.ts               # plugin source
  test/
    session-recorder.test.ts         # plugin tests
  README.md
```

## Testing

```sh
task test:opencode
```

Tests use `bun:test` with mock context and event helpers. Each test file dynamically imports its plugin so environment setup runs first.

## Plugins

### session-recorder

Passively records every conversation to a dual-format archive: `.json` for programmatic analysis, `.md` for human-readable logs.

**Version**: 0.2.0 | **Dependencies**: `@opencode-ai/plugin` only

**Output:**

```
~/.config/opencode/memory/
  index.json                        # aggregate stats across all sessions
  YYYY/MM/
    <timestamp>.json                # structured metrics (written once at finalization)
    <timestamp>.md                  # conversation log (append-only during session)
```

**Configuration** (`~/.config/opencode/session-recorder.json`):

| Field | Default | Description |
|-------|---------|-------------|
| `enabled` | `true` | Toggle recording on/off |
| `debug` | `"error"` | Log level: `off`, `error`, `info`, `debug` |
| `memory_dir` | `~/.config/opencode/memory` | Override output directory |
| `max_recent_sessions` | `10` | Entries kept in `index.json` recent list |

Env override: `SESSION_RECORDER_MEMORY_DIR` sets `memory_dir` (used in tests).

See [docs/agents/memory.md](../../../docs/agents/memory.md) for the full memory architecture, log format spec, and grep patterns.
