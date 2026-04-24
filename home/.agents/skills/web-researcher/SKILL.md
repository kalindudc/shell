---
name: web-researcher
description: Conduct thorough web-based research using web_fetch and web_search tools with delegation. Use when you need external info not in the local codebase -- docs, API references, current practices, error resolution.
---

# Web Research

## When to Skip

- Local codebase answers -- `grep`, `rg`, `ast_query` first
- Well-known language features or stdlib
- Context already provided by the user or gathered this session

## Tool Selection

`web_fetch` is the primary research tool. Use it when you know or can construct the URL:
- Official docs: `https://docs.example.com/api/...`
- GitHub raw content: `https://raw.githubusercontent.com/...`
- Package registries, changelogs, API references

`web_search` is for discovery only. Use it when you genuinely do not know where to look:
- Unfamiliar library or tool with no known docs URL
- Error messages with no obvious cause
- Comparing options you have not encountered before

## Quick Research

1. Construct the URL if possible → `web_fetch` directly
2. Cannot construct URL → single `web_search` → `web_fetch` top 1-2 results
3. Summarize with source URLs

## Thorough Research

For complex questions, comparisons, or critical decisions.

1. Formulate 2-4 distinct queries targeting different angles (see `references/query-tips.md`)
2. Spawn one minion per query following the `delegation` skill pattern:
   ```
   Search for "{query}". Fetch top 2-3 results. Return: summary + source URLs.
   ```
3. Cross-reference findings across minions, flag contradictions, produce consolidated summary with citations

## Rules

- ALWAYS cite source URLs for every claim from web research
- ALWAYS cross-reference multiple sources for critical decisions
- NEVER dump full pages into context -- extract relevant sections only
- Prefer official docs and primary sources over blog posts
- Reformulate queries at least once before giving up on no results
