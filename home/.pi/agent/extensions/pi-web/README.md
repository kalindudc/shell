# pi-web

Lightweight, zero-dependency web search and fetch for the [pi coding agent](https://pi.dev).

Only Node built-ins and pi's own peer packages (`@earendil-works/pi-coding-agent`,
`@earendil-works/pi-ai`, `@earendil-works/pi-tui`) are imported, so there is nothing to
install and nothing to drift against pi upgrades.

## Tools

### `web_search`

Ranked results with title, URL, snippet (and date when the provider has it).

| Param | Description |
| --- | --- |
| `query` / `queries` | One query, or up to 8 run concurrently |
| `numResults` | Per query, 1-20 (default 5) |
| `recency` | `day` / `week` / `month` / `year` |
| `domains` | Restrict to domains; prefix `-` to exclude (`["docs.python.org", "-pinterest.com"]`) |
| `provider` | `auto` (default), `duckduckgo`, `exa`, `brave`, `searxng` |
| `includeContent` | Also fetch readable content of the top results (bounded) |

Providers (`auto` order: `brave → searxng → duckduckgo → exa`, skipping anything unconfigured
and falling through on errors):

| Provider | Key | Notes |
| --- | --- | --- |
| `duckduckgo` | none | Fast (~1s), keyword-style. Bot-checks bursts; falls through to `exa` |
| `exa` | none | Semantic search via Exa's public MCP endpoint, rich highlight snippets. ~3 concurrent |
| `brave` | `BRAVE_API_KEY` | [Brave Search API](https://brave.com/search/api/); best quality, supports recency |
| `searxng` | `SEARXNG_URL` | Self-hosted instance with `json` enabled in `search.formats` |

The output names the provider used per query and any providers that failed first.

### `web_fetch`

URL → readable content. HTML is converted to markdown with boilerplate removed
(nav/footer/aside/scripts/cookie banners); `<main>`, `<article>`, `#mw-content-text`,
`.markdown-body` etc. are preferred over `<body>`. JSON is pretty-printed, text/markdown passes
through, PDFs are extracted with `pdftotext` when installed (`brew install poppler`).

| Param | Description |
| --- | --- |
| `url` / `urls` | One URL, or up to 10 fetched concurrently |
| `mode` | `readable` (default) or `raw` (exact body) |
| `maxChars` | Per-URL content cap (default 30 000; total output always ≤ ~48 KB) |
| `offset` | Continue a long document from this character (served from cache) |
| `find` | Return only passages matching text (case-insensitive) or `/regex/flags`, with line numbers and ~300 chars of context; up to 20 passages, total bounded by `maxChars` |
| `refresh` | Bypass the 15-minute in-memory cache |

`find` regexes always run with the `g` and `m` flags, so `^`/`$` anchor to lines
(`find: "/^## Install/"` jumps to a heading); add `i` for case-insensitive matching.

GitHub URLs are resolved to text-first forms:

| URL | Fetches |
| --- | --- |
| `github.com/o/r` | `README.md` (falls back to the HTML page) |
| `github.com/o/r/blob/ref/path` | raw file |
| `github.com/o/r/tree/ref/path` | directory listing via the API |
| `github.com/o/r/issues/N`, `/pull/N` | title, body and comments via the API |

Set `GITHUB_TOKEN` (or `GH_TOKEN`) to lift the 60 req/h unauthenticated API limit — with the
GitHub CLI installed, `export GH_TOKEN="$(gh auth token)"` in your shell rc is enough. The token
is only ever sent to `api.github.com`.

Every result starts with an informative header the agent can act on:

```
# Markdown - Wikipedia
Source: https://en.wikipedia.org/wiki/Markdown (HTTP 200 · text/html · 36,695 chars · 0.3s · content: <#mw-content-text>)
Showing chars 0–30,000 of 36,695. Continue with offset=30000 (or raise maxChars, or use find="…" to jump to a section).
```

### `/web` command

`/web` shows provider configuration, cache stats and config warnings; `/web clear` empties the
page cache.

## Configuration

Everything works with no configuration. Optional `~/.pi/agent/pi-web.json`
(or `$PI_WEB_CONFIG`); environment variables override file values:

```json
{
  "provider": "auto",
  "braveApiKey": "BSA...",
  "searxngUrl": "http://searx.lan:8080",
  "allowPrivateNetwork": false,
  "timeoutMs": 20000,
  "maxChars": 30000,
  "maxResponseBytes": 5242880,
  "concurrency": 4,
  "userAgent": "..."
}
```

| Env | Overrides |
| --- | --- |
| `BRAVE_API_KEY` | `braveApiKey` |
| `SEARXNG_URL` | `searxngUrl` |
| `PI_WEB_PROVIDER` | `provider` |
| `PI_WEB_ALLOW_PRIVATE` | `allowPrivateNetwork` (`1`/`true`) |
| `PI_WEB_TIMEOUT_MS` | `timeoutMs` |
| `PI_WEB_MAX_CHARS` | `maxChars` |
| `PI_WEB_USER_AGENT` | `userAgent` |

Config is re-read on every call, so edits apply without `/reload`.

## Safety

- Only `http`/`https`. Loopback, private (RFC 1918), link-local/metadata (`169.254.0.0/16`),
  CGNAT, multicast, `localhost`/`.local`/`.internal` and their IPv6 equivalents (including
  IPv4-mapped) are blocked, on the initial request and on every redirect hop.
- Hostnames are resolved once, every returned address is checked, and the TCP connection is
  **pinned to those addresses** (requests go through `node:http`/`node:https` with a custom
  `lookup`, not a second DNS query), so a DNS-rebinding domain cannot pass validation with a
  public IP and then connect to a private one. `Host`, SNI and certificate checks still use the
  hostname. Set `allowPrivateNetwork: true` to fetch local dev servers (resolution and pinning
  still apply; only the block is lifted).
- Response bodies are streamed with a hard byte cap (5 MB default) and per-request timeouts;
  gzip/deflate/brotli (and zstd where Node supports it) are decoded transparently.
- HTML→markdown conversion is linear in page size (a 3 MB Wikipedia article converts in
  ~70 ms), so a large page cannot stall the pi TUI.
- No cookies or credentials are ever sent; API keys are masked in `/web` output.
- Tool output is always truncated under pi's 50 KB limit with an explicit note.

## Layout

```
index.ts    tool registration, output formatting, TUI rendering, /web command
search.ts   providers (duckduckgo, exa, brave, searxng) + routing/fallback
fetch.ts    URL normalization, GitHub rewrites, content-type dispatch, cache, paging, find
html.ts     HTML tokenizer + markdown converter + content-root selection
net.ts      SSRF guard + DNS pinning, safeFetch over node:http(s) (manual redirects, decompression), size-limited reads, limiter
config.ts   config file + env loading
test/       node:test suites (no test deps); fixtures for DuckDuckGo pages
```

## Development

```bash
npm test          # node --test with native TS type-stripping (Node ≥ 22.18)
npm run typecheck # tsc against the installed pi runtime (~/.pi/pkg/pi-<version>)
```

Tests never hit the network: providers are tested against fixtures and `fetch` against a local
`node:http` server (including DNS pinning via an injected resolver and a 2 MB conversion-time
regression guard). `test/_pi-resolve.mjs` maps pi's peer packages to the installed runtime so
`index.ts` can be integration-tested outside pi.

Source uses only erasable TypeScript syntax (no enums, namespaces, or parameter properties) so
it runs unmodified under both pi's jiti loader and Node's `--experimental-strip-types`.
