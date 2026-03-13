---
name: memory-analyzer
description: Analyze past session data to answer questions about usage patterns, costs, and history
---

# Memory Analyzer Skill

## Purpose

Analyze OpenCode session memory to answer user questions about usage, costs, and behavioral patterns. Read-only analysis -- never modify memory files.

Three data tiers, ordered by cost:
1. `index.json` -- fast aggregate stats (session count, model usage, skill/command frequency)
2. `YYYY/MM/<timestamp>.json` -- detailed per-session metrics (tokens, duration, tools, files)
3. `YYYY/MM/<timestamp>.md` -- conversation content (topic search, specific tool output)

## Approach

Start cheap, escalate as needed:
1. Read `index.json` for aggregate queries (model usage, session counts, skill/command frequency)
2. Scan individual `.json` files for detailed analysis (token sums, duration totals, per-project breakdowns)
3. Grep `.md` logs only when conversation content is needed (topic search, specific tool output)

Memory directory: `~/.config/opencode/memory/`

Data field notes:
- `project` may be a hash (older sessions) or readable name (newer sessions) -- use `directory` field for consistent project display
- Extract last path component from `directory` for short project name (e.g., `"shell"`)
- `token_usage` may be all zeros in older sessions -- check per-session before computing costs
- `index.json` `input_tokens` only counts non-cached input (dramatically undercounts) -- always scan `.json` files for cost queries

Query strategies:
- Usage stats: read `index.json` -> `models`, `skills`, `commands` sections
- Cost estimates: ALWAYS scan individual `.json` files (index.json undercounts) -> skip sessions with all-zero tokens -> sum `token_usage` fields (`input` + `cache_read` + `cache_write` + `output`) -> apply pricing
- Session history: scan `.json` files -> filter by date/project/outcome -> use `directory` field for display
- Conversation search: grep `.md` files for keywords

Cost estimation reference (approximate, label as estimates):

| Model | Base Input | Cache Write | Cache Read | Output |
|-------|-----------|-------------|------------|--------|
| claude-opus-4-6 | $5/1M | $6.25/1M | $0.50/1M | $25/1M |
| claude-sonnet-4-5 | $3/1M | $3.75/1M | $0.30/1M | $15/1M |

Cache reads are 0.1x base input price. Cache writes are 1.25x base input price.

Tool usage:
- `read` -- for `index.json` and individual session files
- `bash` -- for `find`/`jq`/`grep` over multiple session files
- `todowrite` -- track analysis progress
- `write` to `./tmp/memory/` -- for analysis reports

## Output

Be concise. Answer the user's question directly with specific numbers and units (tokens, dollars, minutes, counts).

- Label estimates clearly (e.g., "approximately $X based on published pricing")
- When a session has zero token data, skip it for cost calculations and note how many sessions lacked data
- For large result sets, summarize and offer to detail specific items
- Write detailed reports to `./tmp/memory/` if the analysis is complex

## Self-Improvement

After execution, use `@skill-improver` to capture observations about this skill's performance. Before execution, check `SKILL_NOTES.md` for known edge cases.

## Rules

- NEVER modify memory files -- read-only analysis
- NEVER modify source files -- only write to `./tmp/memory/`
- ALWAYS label cost figures as estimates
- ALWAYS start with `index.json` before scanning individual files
- ALWAYS include actual numbers in answers, not vague descriptions
