# Memory Architecture

How agent sessions are recorded, stored, and queried.

## Design Principles

1. **Append-only** -- `.md` logs are never rewritten during a session; `.json` is written once at finalization
2. **Dual-format** -- structured data (JSON) for machines, conversation logs (markdown) for humans
3. **Zero dependencies** -- JSON.parse/stringify only, no yaml or external parsers
4. **Fail-safe** -- every error is logged to `debug.log` and swallowed; recording never interrupts the session

## Directory Layout

```
~/.config/opencode/memory/
  index.json                        # aggregate stats, updated atomically per session
  debug.log                         # plugin debug output (truncated on restart)
  YYYY/MM/
    <timestamp>.json                # session metrics sidecar
    <timestamp>.md                  # conversation log
```

Timestamps use ISO 8601 with colons replaced by hyphens for filesystem safety: `2026-03-03T22-00-47`.

## Session JSON

Written once when a session finalizes (idle, error, or deleted). Contains all queryable metrics:

```json
{
  "session_id": "ses_abc123",
  "project": "shell",
  "title": "Implement plan from ./tmp/plan/",
  "date": "2026-03-03",
  "start_time": "2026-03-03T22:00:47.476Z",
  "end_time": "2026-03-03T23:30:00.000Z",
  "duration_minutes": 89,
  "outcome": "completed",
  "model": "claude-opus-4-6",
  "agent": "build",
  "message_count": 42,
  "compacted": false,
  "skills_used": ["debugger", "plan-generator"],
  "commands_used": ["plan", "implement"],
  "tools_used": { "bash": 15, "edit": 8, "read": 20 },
  "files_touched": ["/tmp/test/foo.ts"],
  "token_usage": { "input": 5000, "output": 3000, "cache_read": 1200, "cache_write": 800 }
}
```

## Conversation Log Format

Role-bracketed format, optimized for `grep` and human scanning:

```markdown
# Session: Implement plan from ./tmp/plan/

[user 22:00:47]
Check the health of all skills

[assistant 22:00:52]
I'll start by reading the skill files.

[tool:read 22:00:53] ~/.config/opencode/skills/debugger/SKILL.md -> 85 lines

[subagent:explore 22:01:10]
> task: Check SKILL_NOTES.md files for consistency

[command 22:02:00] /plan my-feature

[system 22:15:00] context compacted

## Session Summary
- **Outcome**: completed
- **Duration**: 15 minutes
...
```

**Element formats:**

| Element | Format |
|---------|--------|
| User message | `[user HH:MM:SS]` then text |
| Assistant message | `[assistant HH:MM:SS]` then text |
| Tool call | `[tool:NAME HH:MM:SS] description` |
| Subagent | `[subagent:TYPE HH:MM:SS]` then `> key: value` lines |
| System event | `[system HH:MM:SS] description` |
| Command | `[command HH:MM:SS] /name args` |

**Useful grep patterns:**

```sh
grep '^\[user'         session.md   # all user messages
grep '^\[tool:edit'    session.md   # all edit tool calls
grep '^\[subagent:'    session.md   # all subagent work
```

## Index

`index.json` is an aggregate across all sessions, updated atomically (write-to-tmp + rename) at each session finalization:

```json
{
  "last_updated": "2026-03-03",
  "session_count": 14,
  "skills": { "debugger": { "count": 3, "last_used": "2026-03-03" } },
  "commands": { "plan": { "count": 5, "last_used": "2026-03-03" } },
  "models": { "claude-opus-4-6": { "sessions": 10, "input_tokens": 50000, "output_tokens": 30000 } },
  "recent_sessions": [
    { "date": "2026-03-03 22:00", "duration": "89m", "outcome": "completed", "skills": "debugger", "project": "shell" }
  ]
}
```

## Subagent Handling

Subagent sessions (detected by `"subagent"` in the title) are linked to the most recently created parent session in the same project. Subagent output is appended to the parent's `.md` file -- no separate files are created. On subagent completion, the mapping is cleaned up without triggering parent finalization.

## Implementation

The plugin lives at `home/.config/opencode/plugins/session-recorder.ts`. See the [plugin README](../../home/.config/opencode/plugins/README.md) for configuration and testing.
