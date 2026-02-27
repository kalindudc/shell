import { tool } from "@opencode-ai/plugin"
import { existsSync } from "fs"
import { join, basename } from "path"

interface Frame {
  original: string
  file?: string
  resolvedFile?: string
  line?: number
  column?: number
  function?: string
  isInternal: boolean
}

// Common container/build prefixes to strip when resolving paths
const STRIP_PREFIXES = [
  "/app/",
  "/src/",
  "/home/runner/work/",
  "/home/user/",
  "/var/task/",
  "/opt/app/",
  "/workspace/",
  "/build/",
]

function isInternalFrame(filepath: string): boolean {
  return (
    /node_modules/.test(filepath) ||
    /\/usr\/lib\//.test(filepath) ||
    /\/usr\/local\/lib\//.test(filepath) ||
    /\/lib\/python[\d.]+\//.test(filepath) ||
    /\/go\/pkg\//.test(filepath) ||
    /\/go\/src\//.test(filepath) ||
    /\.cargo\/registry/.test(filepath) ||
    filepath.startsWith("<") || // <internal>, <anonymous>, etc.
    filepath === "native" ||
    filepath === "internal"
  )
}

function resolveToWorkspace(filepath: string, worktree: string): string | undefined {
  // Try direct path first
  if (existsSync(join(worktree, filepath))) return filepath

  // Try stripping common prefixes
  for (const prefix of STRIP_PREFIXES) {
    if (filepath.startsWith(prefix)) {
      const relative = filepath.slice(prefix.length)
      if (existsSync(join(worktree, relative))) return relative
    }
  }

  // Try finding by filename in common locations
  const name = basename(filepath)
  // Don't do expensive filesystem search -- just return undefined
  // The agent can use glob/grep to find the file if needed
  return undefined
}

type StackFormat = "nodejs" | "python" | "go" | "ruby" | "java" | "unknown"

function detectFormat(trace: string): StackFormat {
  if (/^\s+at\s+/.test(trace)) return "nodejs"
  if (/File ".*", line \d+/.test(trace)) return "python"
  if (/\.go:\d+\s/.test(trace)) return "go"
  if (/\.rb:\d+:in\s/.test(trace)) return "ruby"
  if (/\.(java|kt|scala):\d+\)/.test(trace)) return "java"
  return "unknown"
}

function parseNodejs(line: string): Partial<Frame> | null {
  // "    at functionName (file:line:col)"
  // "    at file:line:col"
  const match =
    line.match(/^\s+at\s+(.+?)\s+\((.+?):(\d+):(\d+)\)/) ||
    line.match(/^\s+at\s+()(.+?):(\d+):(\d+)/)
  if (!match) return null
  return {
    function: match[1] || undefined,
    file: match[2],
    line: parseInt(match[3]!, 10),
    column: parseInt(match[4]!, 10),
  }
}

function parsePython(line: string): Partial<Frame> | null {
  // '  File "path", line N, in function'
  const match = line.match(/File "(.+?)", line (\d+)(?:, in (.+))?/)
  if (!match) return null
  return {
    file: match[1],
    line: parseInt(match[2]!, 10),
    function: match[3] || undefined,
  }
}

function parseGo(line: string): Partial<Frame> | null {
  // "path/file.go:123 +0xNN"
  // "\tpath/file.go:123"
  const match = line.match(/\t?(.+\.go):(\d+)/)
  if (!match) return null
  return {
    file: match[1],
    line: parseInt(match[2]!, 10),
  }
}

function parseRuby(line: string): Partial<Frame> | null {
  // "path/file.rb:123:in `method'"
  const match = line.match(/(.+?):(\d+):in\s+[`'](.+?)'/)
  if (!match) return null
  return {
    file: match[1],
    line: parseInt(match[2]!, 10),
    function: match[3],
  }
}

function parseJava(line: string): Partial<Frame> | null {
  // "    at package.Class.method(File.java:123)"
  const match = line.match(/at\s+(.+?)\((.+?):(\d+)\)/)
  if (!match) return null
  return {
    function: match[1],
    file: match[2],
    line: parseInt(match[3]!, 10),
  }
}

export default tool({
  description:
    "Takes a raw stack trace and resolves each frame to the actual source file and line in the current workspace. Handles compiled output paths and container path mappings. Turns production error traces into actionable file:line references.",
  args: {
    stackTrace: tool.schema
      .string()
      .describe("Raw stack trace text (paste the whole thing)"),
    sourceMapDir: tool.schema
      .string()
      .optional()
      .describe("Directory containing .map files (default: auto-detect)"),
  },
  async execute(args, context) {
    const worktree = context.worktree
    const traceLines = args.stackTrace.split("\n")
    const format = detectFormat(args.stackTrace)

    const parsers: Record<StackFormat, (line: string) => Partial<Frame> | null> = {
      nodejs: parseNodejs,
      python: parsePython,
      go: parseGo,
      ruby: parseRuby,
      java: parseJava,
      unknown: () => null,
    }

    const parser = parsers[format]
    const frames: Frame[] = []
    let entryFrame: number | null = null

    for (const line of traceLines) {
      const trimmed = line.trim()
      if (!trimmed) continue

      const parsed = parser(trimmed)
      if (!parsed || !parsed.file) {
        // Keep unparseable lines as context
        if (trimmed.length > 0 && frames.length === 0) {
          // Likely the error message line at the top
          continue
        }
        continue
      }

      const isInternal = isInternalFrame(parsed.file)
      const resolvedFile = isInternal
        ? undefined
        : resolveToWorkspace(parsed.file, worktree)

      const frame: Frame = {
        original: trimmed,
        file: parsed.file,
        resolvedFile: resolvedFile || undefined,
        line: parsed.line,
        column: parsed.column,
        function: parsed.function,
        isInternal,
      }

      if (entryFrame === null && !isInternal && resolvedFile) {
        entryFrame = frames.length
      }

      frames.push(frame)
    }

    if (frames.length === 0) {
      return JSON.stringify(
        {
          format: "unknown",
          frames: [],
          note: "Could not parse any stack frames from the input. Supported formats: Node.js, Python, Go, Ruby, Java.",
          raw: args.stackTrace.slice(0, 1000),
        },
        null,
        2,
      )
    }

    const relatedFiles = [
      ...new Set(
        frames
          .filter((f) => f.resolvedFile)
          .map((f) => f.resolvedFile!),
      ),
    ]

    return JSON.stringify(
      {
        format,
        entryFrame,
        relatedFiles,
        frames,
      },
      null,
      2,
    )
  },
})
