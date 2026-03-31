/**
 * Web Research Extension
 *
 * Registers two tools:
 * - web_fetch: Fetch a URL and convert HTML to LLM-friendly markdown
 * - web_search: Search the web via Exa AI (free, no API key)
 */

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { Type } from "@sinclair/typebox";
import TurndownService from "turndown";
import { Readability } from "@mozilla/readability";
import { parseHTML } from "linkedom";
import { writeFileSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { randomBytes } from "node:crypto";

// Constants

const MAX_CONTENT_BYTES = 50 * 1024; // 50KB
const MAX_CONTENT_LINES = 2000;

const CHROME_UA =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36";

const EXA_MCP_URL = "https://mcp.exa.ai/mcp";

// Helpers

function truncate(text: string, maxBytes: number, maxLines: number): string {
  const lines = text.split("\n");
  const totalBytes = Buffer.byteLength(text, "utf-8");

  if (lines.length <= maxLines && totalBytes <= maxBytes) return text;

  // Head-truncate: keep first N lines/bytes
  const out: string[] = [];
  let bytes = 0;
  let hitBytes = false;
  for (let i = 0; i < lines.length && i < maxLines; i++) {
    const size = Buffer.byteLength(lines[i], "utf-8") + (i > 0 ? 1 : 0);
    if (bytes + size > maxBytes) {
      hitBytes = true;
      break;
    }
    out.push(lines[i]);
    bytes += size;
  }

  const removed = hitBytes ? totalBytes - bytes : lines.length - out.length;
  const unit = hitBytes ? "bytes" : "lines";

  // Save full content to temp file
  const fullPath = join(tmpdir(), `pi-web-fetch-${randomBytes(8).toString("hex")}.md`);
  writeFileSync(fullPath, text, "utf-8");

  const preview = out.join("\n");
  const hint = `The tool call succeeded but the output was truncated. Full output saved to: ${fullPath}\nUse read with offset/limit to view specific sections, or grep to search the full content.`;

  return `${preview}\n\n...${removed} ${unit} truncated...\n\n${hint}`;
}

function isHtml(contentType: string): boolean {
  return contentType.includes("text/html") || contentType.includes("application/xhtml");
}

function isJson(contentType: string): boolean {
  return contentType.includes("application/json") || contentType.includes("+json");
}

function isText(contentType: string): boolean {
  return contentType.includes("text/");
}

function htmlToMarkdown(html: string, url: string): string {
  const { document } = parseHTML(html);

  // Use Readability to extract article content
  const reader = new Readability(document, { charThreshold: 0 });
  const article = reader.parse();

  const turndown = new TurndownService({
    headingStyle: "atx",
    codeBlockStyle: "fenced",
  });

  if (article?.content) {
    const markdown = turndown.turndown(article.content);
    const title = article.title ? `# ${article.title}\n\n` : "";
    return title + markdown;
  }

  // Fallback: convert the whole body if Readability couldn't extract
  const body = document.querySelector("body");
  if (body) {
    return turndown.turndown(body.innerHTML);
  }

  return turndown.turndown(html);
}

interface SearchResult {
  title: string;
  url: string;
  snippet: string;
}

function parseExaResponse(text: string): SearchResult[] {
  // Exa returns SSE format: "data: {json}\n\n"
  const results: SearchResult[] = [];
  const lines = text.split("\n");

  for (const line of lines) {
    if (!line.startsWith("data: ")) continue;

    try {
      const data = JSON.parse(line.slice(6));
      const content = data?.result?.content?.[0]?.text;
      if (!content) continue;

      // Parse the structured text response into individual results
      // Format: "Title: ...\nURL: ...\nPublished: ...\nHighlights:\n...\n---\n"
      const blocks = content.split(/\n---\n/).filter((b: string) => b.trim());
      for (const block of blocks) {
        const titleMatch = block.match(/Title:\s*(.+)/);
        const urlMatch = block.match(/URL:\s*(.+)/);
        const highlightsMatch = block.match(/Highlights:\n([\s\S]*?)$/);

        if (titleMatch && urlMatch) {
          results.push({
            title: titleMatch[1].trim(),
            url: urlMatch[1].trim(),
            snippet: highlightsMatch
              ? highlightsMatch[1].trim().split("\n").slice(0, 2).join(" ").slice(0, 200)
              : "",
          });
        }
      }
    } catch {
      // skip unparseable lines
    }
  }

  return results;
}

// Extension

export default function (pi: ExtensionAPI) {
  // web_fetch
  pi.registerTool({
    name: "web_fetch",
    label: "Web Fetch",
    description:
      "Fetch a URL and return its content as LLM-friendly markdown. Converts HTML pages to clean markdown using Readability + Turndown. JSON and plain text are returned directly.",
    promptSnippet:
      "web_fetch: Fetch a URL and return its content as LLM-friendly markdown",
    promptGuidelines: [
      "web_fetch is your primary research tool -- use it to retrieve documentation, API references, and technical content directly when you know or can construct the URL",
      "Prefer web_fetch over bash + curl for web pages; use bash + curl only for raw API calls that return JSON",
      "For research tasks, go to web_fetch first with known URLs (official docs, GitHub raw content, API references) before falling back to web_search",
    ],
    parameters: Type.Object({
      url: Type.String({
        description: "URL to fetch (http:// or https://)",
      }),
    }),
    async execute(_toolCallId, args) {
      const { url } = args;

      // Validate URL
      let parsed: URL;
      try {
        parsed = new URL(url);
      } catch {
        return {
          content: [{ type: "text", text: `Invalid URL: ${url}` }],
          details: {},
        };
      }

      if (!parsed.protocol.startsWith("http")) {
        return {
          content: [
            {
              type: "text",
              text: `Only http:// and https:// URLs are supported, got: ${parsed.protocol}`,
            },
          ],
          details: {},
        };
      }

      try {
        const response = await fetch(url, {
          headers: {
            "User-Agent": CHROME_UA,
            Accept:
              "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.9",
          },
          redirect: "follow",
          signal: AbortSignal.timeout(30_000),
        });

        if (!response.ok) {
          return {
            content: [
              {
                type: "text",
                text: `HTTP ${response.status} ${response.statusText} for ${url}`,
              },
            ],
            details: {},
          };
        }

        const contentType = (
          response.headers.get("content-type") || "text/plain"
        ).toLowerCase();
        const body = await response.text();

        let content: string;

        if (isHtml(contentType)) {
          content = htmlToMarkdown(body, url);
        } else if (isJson(contentType)) {
          try {
            content = JSON.stringify(JSON.parse(body), null, 2);
          } catch {
            content = body;
          }
        } else if (isText(contentType)) {
          content = body;
        } else {
          return {
            content: [
              {
                type: "text",
                text: `Unsupported content type: ${contentType} for ${url}`,
              },
            ],
            details: {},
          };
        }

        content = truncate(content, MAX_CONTENT_BYTES, MAX_CONTENT_LINES);

        return {
          content: [{ type: "text", text: content }],
          details: {},
        };
      } catch (e) {
        const message =
          e instanceof Error ? e.message : "Unknown error";
        return {
          content: [
            {
              type: "text",
              text: `Failed to fetch ${url}: ${message}`,
            },
          ],
          details: {},
        };
      }
    },
  });

  // web_search
  pi.registerTool({
    name: "web_search",
    label: "Web Search",
    description:
      "Search the web to discover relevant URLs and information. Uses Exa AI — no API key required. Returns titles, URLs, and snippets.",
    promptSnippet:
      "web_search: Search the web to discover relevant URLs and information",
    promptGuidelines: [
      "Use web_search only when you genuinely do not know the URL -- for unfamiliar topics, discovering new libraries, or finding resources you cannot construct a URL for",
      "Do NOT use web_search when you can construct the URL directly (e.g. official docs, GitHub repos, known API references) -- use web_fetch instead",
    ],
    parameters: Type.Object({
      query: Type.String({
        description: "Search query",
      }),
      count: Type.Optional(
        Type.Number({
          description: "Number of results to return (default: 5, max: 20)",
          default: 5,
          maximum: 20,
        }),
      ),
    }),
    async execute(_toolCallId, args) {
      const { query, count = 5 } = args;
      const numResults = Math.min(count, 20);

      try {
        const response = await fetch(EXA_MCP_URL, {
          method: "POST",
          headers: {
            "Accept": "application/json, text/event-stream",
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            jsonrpc: "2.0",
            id: 1,
            method: "tools/call",
            params: {
              name: "web_search_exa",
              arguments: {
                query,
                type: "auto",
                numResults,
                livecrawl: "fallback",
              },
            },
          }),
          signal: AbortSignal.timeout(25_000),
        });

        if (!response.ok) {
          const errorText = await response.text();
          return {
            content: [
              {
                type: "text",
                text: `Search failed: HTTP ${response.status}: ${errorText}`,
              },
            ],
            details: {},
          };
        }

        const text = await response.text();
        const results = parseExaResponse(text);

        if (results.length === 0) {
          return {
            content: [
              {
                type: "text",
                text: `No results found for: ${query}`,
              },
            ],
            details: {},
          };
        }

        const formatted = results
          .map(
            (r, i) =>
              `${i + 1}. **${r.title}**\n   ${r.url}\n   ${r.snippet || "No snippet available"}`,
          )
          .join("\n\n");

        return {
          content: [
            {
              type: "text",
              text: `## Search results for: ${query}\n\n${formatted}`,
            },
          ],
          details: {},
        };
      } catch (e) {
        const message =
          e instanceof Error ? e.message : "Unknown error";
        return {
          content: [
            {
              type: "text",
              text: `Search failed: ${message}`,
            },
          ],
          details: {},
        };
      }
    },
  });
}
