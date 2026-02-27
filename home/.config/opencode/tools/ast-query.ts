import { tool } from "@opencode-ai/plugin"

const MAX_MATCHES = 20

export default tool({
  description:
    "Search code using structural AST patterns (via ast-grep). Finds code by structure, not just text -- e.g. 'all empty catch blocks', 'functions returning Promise', 'React components with children prop'. Requires ast-grep CLI (sg).",
  args: {
    pattern: tool.schema
      .string()
      .describe(
        "ast-grep pattern. Use $NAME for captures, $$$ for variadic. E.g. 'catch ($ERR) { }' or 'function $NAME($$$): Promise<$RET>'",
      ),
    language: tool.schema
      .string()
      .describe("Language: ts, js, py, go, rust, ruby, java, etc."),
    path: tool.schema
      .string()
      .optional()
      .describe("Directory to search (default: project root)"),
  },
  async execute(args, context) {
    const searchPath = args.path || context.worktree

    try {
      const result = await Bun.$`sg --pattern ${args.pattern} --lang ${args.language} --json ${searchPath}`
        .nothrow()
        .quiet()
        .text()

      let matches: Array<Record<string, unknown>>
      try {
        matches = JSON.parse(result)
      } catch {
        return `ast-grep returned non-JSON output:\n${result.slice(0, 500)}`
      }

      if (!Array.isArray(matches) || matches.length === 0) {
        return "No matches found."
      }

      const totalMatches = matches.length
      const limited = matches.slice(0, MAX_MATCHES)

      const formatted = limited.map((m: Record<string, unknown>) => ({
        file: m.file,
        line: (m.range as Record<string, Record<string, number>>)?.start?.line,
        code: (m.text as string)?.slice(0, 200),
      }))

      return JSON.stringify(
        {
          totalMatches,
          showing: formatted.length,
          matches: formatted,
          ...(totalMatches > MAX_MATCHES
            ? {
                note: `${totalMatches - MAX_MATCHES} additional matches not shown. Narrow your pattern or path.`,
              }
            : {}),
        },
        null,
        2,
      )
    } catch (e) {
      const which = await Bun.$`which sg`.nothrow().quiet().text().catch(() => "")
      if (!which.trim()) {
        return "ast-grep (sg) is not installed. Install with: brew install ast-grep"
      }
      return `ast-grep error: ${(e as Error).message}`
    }
  },
})
