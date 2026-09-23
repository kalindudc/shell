---
name: web-researcher
description: Conduct thorough web-based research using the web_fetch and web_search tools (pi-web extension) with delegation. Use when you need external info not in the local codebase -- docs, API references, current practices, error resolution.
---

# Web Research

## When to Skip

- Local codebase answers -- `grep`, `rg`, `ast_query` first
- Well-known language features or stdlib
- Context already provided by the user or gathered this session

## Tool Selection

Both tools come from the `pi-web` extension (`~/.pi/agent/extensions/pi-web`). Run `/web` to see provider and cache status.

`web_fetch` is the primary research tool. Use it when you know or can construct the URL:
- Official docs: `https://docs.example.com/api/...`
- GitHub: repo URL returns the README; `blob` URLs return the raw file; `tree` URLs return a listing; issue/PR URLs return the full thread
- Package registries, changelogs, API references, JSON endpoints, PDFs (text via `pdftotext`)

`web_fetch` options that keep context small:
- `find: "term"` returns only matching passages with line numbers -- use it to locate a section in long docs before reading. Plain text is case-insensitive; `find: "/^## Install/"` is a regex anchored to line starts (`g` and `m` are always on; add `i` for case-insensitive)
- `offset: N` continues a long document from character N (served from cache, no re-download); the output tells you the next offset
- `maxChars` bounds each page; `urls: [...]` fetches several pages concurrently; `mode: "raw"` returns the exact body (HTML source, JSON)

`web_search` is for discovery only. Use it when you genuinely do not know where to look:
- Unfamiliar library or tool with no known docs URL
- Error messages with no obvious cause
- Comparing options you have not encountered before

`web_search` options:
- `queries: [...]` runs 2-4 varied queries concurrently in ONE call -- prefer this over sequential single queries
- `domains: ["docs.python.org"]` restricts results; `"-reddit.com"` excludes
- `recency: "month"` (day/week/month/year) for evolving topics
- `includeContent: true` also returns the readable content of the top results when snippets are not enough
- Keyless by default (DuckDuckGo, then Exa); the output names the provider used and any fallbacks

## Quick Research

1. Construct the URL if possible → `web_fetch` directly (add `find` when you know the section you need)
2. Cannot construct URL → single `web_search` → `web_fetch` top 1-2 results
3. Summarize with source URLs

## Thorough Research

For complex questions, comparisons, or critical decisions.

1. Formulate 2-4 distinct queries targeting different angles (see `references/query-tips.md`)
2. Run them in one `web_search` call with `queries: [...]` to see the landscape, then either read the top results inline with `web_fetch` or, for large surveys, spawn one minion per angle following the `delegation` skill pattern:
   ```
   Use web_search for "{query}", then web_fetch the top 2-3 results (use find/offset to read only relevant sections). Return: summary + source URLs.
   ```
3. Cross-reference findings across minions, flag contradictions, produce consolidated summary with citations

## Rules

- ALWAYS cite source URLs for every claim from web research
- ALWAYS cross-reference multiple sources for critical decisions
- NEVER dump full pages into context -- use `web_fetch` with `find` or `offset`/`maxChars` to extract relevant sections only
- If `web_fetch` reports a JavaScript-rendered page, try the site's docs/raw/API URL or a `web_search` for the same content instead of retrying
- Prefer official docs and primary sources over blog posts
- Reformulate queries at least once before giving up on no results
