import { tool } from "@opencode-ai/plugin"

type FileCategory = "source" | "test" | "config" | "migration" | "docs" | "generated"

function categorize(filepath: string): FileCategory {
  const lower = filepath.toLowerCase()

  // Test files
  if (
    /\/(tests?|__tests?__|spec)\//i.test(filepath) ||
    /[._](test|spec)\.[^/]+$/.test(lower) ||
    /_test\.[^/]+$/.test(lower)
  )
    return "test"

  // Docs
  if (/\/(docs?)\//i.test(filepath) || /\.(md|mdx|rst|txt)$/i.test(lower)) return "docs"

  // Config
  if (
    /\.(json|ya?ml|toml|ini|env[^/]*)$/i.test(lower) ||
    /(dockerfile|docker-compose|makefile|taskfile|\.config)/i.test(lower) ||
    /\.(lock|lockb)$/i.test(lower)
  )
    return "config"

  // Migration
  if (/\/(migrations?|migrate)\//i.test(filepath)) return "migration"

  // Generated
  if (
    /\/(generated|gen)\//i.test(filepath) ||
    /\.(gen|generated|pb)\.[^/]+$/i.test(lower)
  )
    return "generated"

  return "source"
}

type CommitType = "feat" | "fix" | "refactor" | "docs" | "test" | "chore"

function suggestCommitType(
  files: Array<{ status: string; category: FileCategory }>,
): CommitType {
  const categories = new Set(files.map((f) => f.category))
  const statuses = new Set(files.map((f) => f.status))

  if (categories.size === 1 && categories.has("docs")) return "docs"
  if (categories.size === 1 && categories.has("test")) return "test"
  if (categories.size === 1 && categories.has("config")) return "chore"

  if (statuses.has("A") && !statuses.has("D")) return "feat"
  if (statuses.has("R")) return "refactor"

  const sourceFiles = files.filter((f) => f.category === "source")
  if (sourceFiles.length > 0 && sourceFiles.length <= 3) return "fix"

  return "feat"
}

export default tool({
  description:
    "Returns a structured summary of git changes: files changed, insertions/deletions, auto-categorization (source/test/config/docs/migration), and suggested commit type. Saves chaining 3-5 git commands and parsing raw diff output.",
  args: {
    base: tool.schema
      .string()
      .optional()
      .describe(
        "Base ref (default: HEAD for uncommitted, or main for branch comparison)",
      ),
    target: tool.schema
      .string()
      .optional()
      .describe("Target ref (default: working tree)"),
    includeStaged: tool.schema
      .boolean()
      .optional()
      .describe("Include staged changes (default: true)"),
  },
  async execute(args, context) {
    const cwd = context.worktree

    // Helper: run a git diff command with the given format flag and optional refs
    async function gitDiff(formatFlag: string): Promise<string> {
      if (args.base && args.target) {
        return Bun.$`git diff ${formatFlag} ${args.base} ${args.target}`.nothrow().quiet().cwd(cwd).text()
      } else if (args.base) {
        return Bun.$`git diff ${formatFlag} ${args.base}`.nothrow().quiet().cwd(cwd).text()
      } else if (args.includeStaged !== false) {
        return Bun.$`git diff ${formatFlag} HEAD`.nothrow().quiet().cwd(cwd).text()
      } else {
        return Bun.$`git diff ${formatFlag}`.nothrow().quiet().cwd(cwd).text()
      }
    }

    try {
      const [numstatOut, nameStatusOut] = await Promise.all([
        gitDiff("--numstat").catch(() => ""),
        gitDiff("--name-status").catch(() => ""),
      ])

      if (!numstatOut.trim() && !nameStatusOut.trim()) {
        return JSON.stringify({ message: "No changes found.", files: [], summary: { totalFiles: 0, insertions: 0, deletions: 0, categories: {} } }, null, 2)
      }

      // Parse --numstat: additions \t deletions \t filepath
      const numstatMap = new Map<string, { insertions: number; deletions: number }>()
      for (const line of numstatOut.trim().split("\n").filter(Boolean)) {
        const [add, del, ...pathParts] = line.split("\t")
        const filepath = pathParts.join("\t") // handle renames with => in path
        numstatMap.set(filepath, {
          insertions: add === "-" ? 0 : parseInt(add, 10) || 0,
          deletions: del === "-" ? 0 : parseInt(del, 10) || 0,
        })
      }

      // Parse --name-status: status \t filepath
      const files: Array<{
        file: string
        status: string
        category: FileCategory
        insertions: number
        deletions: number
      }> = []

      for (const line of nameStatusOut.trim().split("\n").filter(Boolean)) {
        const parts = line.split("\t")
        const status = parts[0]![0]! // First char: A, M, D, R, etc.
        const filepath = parts.length > 2 ? parts[2]! : parts[1]! // Renames: old \t new
        const stats = numstatMap.get(filepath) ||
          numstatMap.get(parts[1]!) ||
          { insertions: 0, deletions: 0 }

        files.push({
          file: filepath,
          status,
          category: categorize(filepath),
          insertions: stats.insertions,
          deletions: stats.deletions,
        })
      }

      // Compute summary
      const totalInsertions = files.reduce((a, f) => a + f.insertions, 0)
      const totalDeletions = files.reduce((a, f) => a + f.deletions, 0)
      const categoryBreakdown: Record<string, number> = {}
      for (const f of files) {
        categoryBreakdown[f.category] = (categoryBreakdown[f.category] || 0) + 1
      }

      return JSON.stringify(
        {
          summary: {
            totalFiles: files.length,
            insertions: totalInsertions,
            deletions: totalDeletions,
            categories: categoryBreakdown,
            suggestedCommitType: suggestCommitType(files),
          },
          files,
        },
        null,
        2,
      )
    } catch (e) {
      return `git diff error: ${(e as Error).message}`
    }
  },
})
