import { tool } from "@opencode-ai/plugin"

const MAX_RELATED_FILES = 10

interface BlameLine {
  lineNum: number
  content: string
  commitHash: string
}

interface CommitInfo {
  hash: string
  author: string
  email: string
  date: string
  message: string
  relatedFiles: string[]
  prNumber?: string
}

function extractPrNumber(message: string): string | undefined {
  // Common patterns: "... (#123)", "Merge pull request #123"
  const match = message.match(/\(#(\d+)\)/) || message.match(/pull request #(\d+)/i)
  return match?.[1]
}

function parsePorcelainBlame(raw: string): BlameLine[] {
  const lines: BlameLine[] = []
  const rawLines = raw.split("\n")
  let i = 0

  while (i < rawLines.length) {
    const headerLine = rawLines[i]
    if (!headerLine) {
      i++
      continue
    }

    // Header: <hash> <orig-line> <final-line> [<num-lines>]
    const headerMatch = headerLine.match(/^([0-9a-f]{40})\s+(\d+)\s+(\d+)/)
    if (!headerMatch) {
      i++
      continue
    }

    const commitHash = headerMatch[1]!
    const finalLine = parseInt(headerMatch[3]!, 10)

    // Skip header fields until we hit the content line (starts with \t)
    i++
    while (i < rawLines.length && !rawLines[i]!.startsWith("\t")) {
      i++
    }

    if (i < rawLines.length && rawLines[i]!.startsWith("\t")) {
      lines.push({
        lineNum: finalLine,
        content: rawLines[i]!.slice(1), // Remove leading tab
        commitHash,
      })
    }
    i++
  }

  return lines
}

export default tool({
  description:
    "Returns structured blame information for a code region: who changed each line, when, why (commit message), and what other files were changed in the same commits. Replaces the 4+ command chain of git blame + git show + git log + gh pr view.",
  args: {
    file: tool.schema.string().describe("File path"),
    startLine: tool.schema.number().describe("Start line"),
    endLine: tool.schema.number().describe("End line"),
    depth: tool.schema
      .number()
      .optional()
      .describe("Max commits to show per line (default: 1, most recent)"),
  },
  async execute(args, context) {
    const cwd = context.worktree

    try {
      const lineRange = `${args.startLine},${args.endLine}`
      const blameRaw = await Bun.$`git blame --porcelain -L ${lineRange} -- ${args.file}`
        .nothrow()
        .quiet()
        .cwd(cwd)
        .text()

      if (!blameRaw.trim()) {
        return JSON.stringify({ error: "No blame data returned. Check that the file and line range exist." }, null, 2)
      }

      const blameLines = parsePorcelainBlame(blameRaw)

      if (blameLines.length === 0) {
        return JSON.stringify({ error: "Could not parse blame output." }, null, 2)
      }

      // Get unique commit hashes
      const uniqueHashes = [...new Set(blameLines.map((l) => l.commitHash))]

      // Enrich each commit
      const commits: CommitInfo[] = await Promise.all(
        uniqueHashes.map(async (hash) => {
          try {
            const formatStr = "%H%x00%an%x00%ae%x00%aI%x00%s"
            const showRaw = await Bun.$`git show --stat --format=${formatStr} ${hash}`
              .nothrow()
              .quiet()
              .cwd(cwd)
              .text()

            const firstLine = showRaw.split("\n")[0] || ""
            const [, author, email, date, ...messageParts] = firstLine.split("\x00")
            const message = messageParts.join("\x00") // Re-join in case message contains NUL (unlikely)

            // Extract related files from --stat output (lines after the first)
            const statLines = showRaw.split("\n").slice(1).filter((l) => l.includes("|"))
            const relatedFiles = statLines
              .map((l) => l.trim().split(/\s+\|/)[0]?.trim())
              .filter(Boolean)
              .slice(0, MAX_RELATED_FILES) as string[]

            return {
              hash,
              author: author || "unknown",
              email: email || "",
              date: date || "",
              message: message || "",
              relatedFiles,
              prNumber: extractPrNumber(message || ""),
            }
          } catch {
            return {
              hash,
              author: "unknown",
              email: "",
              date: "",
              message: "Could not fetch commit details",
              relatedFiles: [],
            }
          }
        }),
      )

      // Build line-level output referencing commits by hash
      const lines = blameLines.map((l) => ({
        lineNum: l.lineNum,
        content: l.content,
        commitHash: l.commitHash.slice(0, 8),
      }))

      return JSON.stringify({ lines, commits }, null, 2)
    } catch (e) {
      return `git blame error: ${(e as Error).message}`
    }
  },
})
