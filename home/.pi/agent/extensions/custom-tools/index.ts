/**
 * Custom Tools Extension
 *
 * Registers 5 tools:
 * - ast_query: Structural AST pattern search via ast-grep
 * - git_blame: Blame context for a code region
 * - git_diff_summary: Structured diff summary with categorization
 * - stack_trace_resolve: Resolve stack traces to workspace paths
 * - test_run_parsed: Run tests with structured output parsing
 */

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { Type } from "@sinclair/typebox";
import { spawn } from "child_process";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function exec(
  cmd: string,
  args: string[],
  options: { cwd?: string; timeout?: number } = {},
): Promise<{ stdout: string; stderr: string; exitCode: number }> {
  return new Promise((resolve) => {
    const proc = spawn(cmd, args, {
      cwd: options.cwd,
      stdio: ["ignore", "pipe", "pipe"],
      timeout: options.timeout,
    });

    let stdout = "";
    let stderr = "";

    proc.stdout.on("data", (d: Buffer) => {
      stdout += d.toString();
    });
    proc.stderr.on("data", (d: Buffer) => {
      stderr += d.toString();
    });

    proc.on("close", (code) => {
      resolve({ stdout, stderr, exitCode: code ?? 1 });
    });

    proc.on("error", (err) => {
      resolve({ stdout, stderr: err.message, exitCode: 1 });
    });
  });
}

function execShell(
  command: string,
  options: { cwd?: string; timeout?: number } = {},
): Promise<{ stdout: string; stderr: string; exitCode: number }> {
  return exec("bash", ["-c", command], options);
}

// ---------------------------------------------------------------------------
// Extension
// ---------------------------------------------------------------------------

const MAX_MATCHES = 20;
const MAX_RELATED_FILES = 10;
const RAW_OUTPUT_MAX_LINES = 200;
const TEST_TIMEOUT_MS = 5 * 60 * 1000;

export default function (pi: ExtensionAPI) {
  // =========================================================================
  // 1. ast_query
  // =========================================================================
  pi.registerTool({
    name: "ast_query",
    label: "AST Query",
    description:
      "Search code using structural AST patterns (via ast-grep). Finds code by structure, not just text -- e.g. 'all empty catch blocks', 'functions returning Promise'. Requires ast-grep CLI (sg).",
    parameters: Type.Object({
      pattern: Type.String({
        description:
          "ast-grep pattern. Use $NAME for captures, $$$ for variadic. E.g. 'catch ($ERR) { }' or 'function $NAME($$$): Promise<$RET>'",
      }),
      language: Type.String({
        description: "Language: ts, js, py, go, rust, ruby, java, etc.",
      }),
      path: Type.Optional(
        Type.String({ description: "Directory to search (default: project root)" }),
      ),
    }),
    async execute(_toolCallId, args, _signal, _onUpdate, ctx) {
      const searchPath = args.path || ctx.cwd;

      const { stdout, stderr, exitCode } = await exec(
        "sg",
        ["--pattern", args.pattern, "--lang", args.language, "--json", searchPath],
        { cwd: ctx.cwd },
      );

      if (exitCode !== 0 && !stdout.trim()) {
        // Check if sg is installed
        const which = await execShell("which sg");
        if (!which.stdout.trim()) {
          return { content: [{ type: "text", text: "ast-grep (sg) is not installed. Install with: brew install ast-grep" }], details: {} };
        }
        return { content: [{ type: "text", text: `ast-grep error: ${stderr || "unknown error"}` }], details: {} };
      }

      let matches: Array<Record<string, unknown>>;
      try {
        matches = JSON.parse(stdout);
      } catch {
        return { content: [{ type: "text", text: `ast-grep returned non-JSON output:\n${stdout.slice(0, 500)}` }], details: {} };
      }

      if (!Array.isArray(matches) || matches.length === 0) {
        return { content: [{ type: "text", text: "No matches found." }], details: {} };
      }

      const totalMatches = matches.length;
      const limited = matches.slice(0, MAX_MATCHES);

      const formatted = limited.map((m: Record<string, unknown>) => ({
        file: m.file,
        line: (m.range as Record<string, Record<string, number>>)?.start?.line,
        code: (m.text as string)?.slice(0, 200),
      }));

      return {
        content: [{ type: "text", text: JSON.stringify(
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
        ) }],
        details: {},
      };
    },
  });

  // =========================================================================
  // 2. git_blame
  // =========================================================================
  pi.registerTool({
    name: "git_blame",
    label: "Git Blame Context",
    description:
      "Returns structured blame information for a code region: who changed each line, when, why (commit message), and what other files were changed in the same commits.",
    parameters: Type.Object({
      file: Type.String({ description: "File path" }),
      startLine: Type.Number({ description: "Start line" }),
      endLine: Type.Number({ description: "End line" }),
      depth: Type.Optional(
        Type.Number({
          description: "Max commits to show per line (default: 1, most recent)",
        }),
      ),
    }),
    async execute(_toolCallId, args, _signal, _onUpdate, ctx) {
      const cwd = ctx.cwd;
      const lineRange = `${args.startLine},${args.endLine}`;

      const { stdout: blameRaw } = await exec(
        "git",
        ["blame", "--porcelain", "-L", lineRange, "--", args.file],
        { cwd },
      );

      if (!blameRaw.trim()) {
        return {
          content: [{ type: "text", text: JSON.stringify(
            { error: "No blame data returned. Check that the file and line range exist." },
            null,
            2,
          ) }],
          details: {},
        };
      }

      // Parse porcelain blame output
      const blameLines: Array<{
        lineNum: number;
        content: string;
        commitHash: string;
      }> = [];
      const rawLines = blameRaw.split("\n");
      let i = 0;

      while (i < rawLines.length) {
        const headerLine = rawLines[i];
        if (!headerLine) {
          i++;
          continue;
        }

        const headerMatch = headerLine.match(/^([0-9a-f]{40})\s+(\d+)\s+(\d+)/);
        if (!headerMatch) {
          i++;
          continue;
        }

        const commitHash = headerMatch[1]!;
        const finalLine = parseInt(headerMatch[3]!, 10);

        i++;
        while (i < rawLines.length && !rawLines[i]!.startsWith("\t")) {
          i++;
        }

        if (i < rawLines.length && rawLines[i]!.startsWith("\t")) {
          blameLines.push({
            lineNum: finalLine,
            content: rawLines[i]!.slice(1),
            commitHash,
          });
        }
        i++;
      }

      if (blameLines.length === 0) {
        return {
          content: [{ type: "text", text: JSON.stringify({ error: "Could not parse blame output." }, null, 2) }],
          details: {},
        };
      }

      // Enrich unique commits
      const uniqueHashes = [...new Set(blameLines.map((l) => l.commitHash))];
      const commits = await Promise.all(
        uniqueHashes.map(async (hash) => {
          try {
            const formatStr = "%H%x00%an%x00%ae%x00%aI%x00%s";
            const { stdout: showRaw } = await exec(
              "git",
              ["show", "--stat", `--format=${formatStr}`, hash],
              { cwd },
            );

            const firstLine = showRaw.split("\n")[0] || "";
            const [, author, email, date, ...messageParts] = firstLine.split("\x00");
            const message = messageParts.join("\x00");

            const statLines = showRaw
              .split("\n")
              .slice(1)
              .filter((l) => l.includes("|"));
            const relatedFiles = statLines
              .map((l) => l.trim().split(/\s+\|/)[0]?.trim())
              .filter(Boolean)
              .slice(0, MAX_RELATED_FILES) as string[];

            // Extract PR number from commit message
            const prMatch =
              (message || "").match(/\(#(\d+)\)/) ||
              (message || "").match(/pull request #(\d+)/i);

            return {
              hash,
              author: author || "unknown",
              email: email || "",
              date: date || "",
              message: message || "",
              relatedFiles,
              prNumber: prMatch?.[1],
            };
          } catch {
            return {
              hash,
              author: "unknown",
              email: "",
              date: "",
              message: "Could not fetch commit details",
              relatedFiles: [],
            };
          }
        }),
      );

      const lines = blameLines.map((l) => ({
        lineNum: l.lineNum,
        content: l.content,
        commitHash: l.commitHash.slice(0, 8),
      }));

      return {
        content: [{ type: "text", text: JSON.stringify({ lines, commits }, null, 2) }],
        details: {},
      };
    },
  });

  // =========================================================================
  // 3. git_diff_summary
  // =========================================================================

  type FileCategory = "source" | "test" | "config" | "migration" | "docs" | "generated";

  function categorize(filepath: string): FileCategory {
    const lower = filepath.toLowerCase();
    if (
      /\/(tests?|__tests?__|spec)\//i.test(filepath) ||
      /[._](test|spec)\.[^/]+$/.test(lower) ||
      /_test\.[^/]+$/.test(lower)
    )
      return "test";
    if (/\/(docs?)\//i.test(filepath) || /\.(md|mdx|rst|txt)$/i.test(lower))
      return "docs";
    if (
      /\.(json|ya?ml|toml|ini|env[^/]*)$/i.test(lower) ||
      /(dockerfile|docker-compose|makefile|taskfile|\.config)/i.test(lower) ||
      /\.(lock|lockb)$/i.test(lower)
    )
      return "config";
    if (/\/(migrations?|migrate)\//i.test(filepath)) return "migration";
    if (
      /\/(generated|gen)\//i.test(filepath) ||
      /\.(gen|generated|pb)\.[^/]+$/i.test(lower)
    )
      return "generated";
    return "source";
  }

  type CommitType = "feat" | "fix" | "refactor" | "docs" | "test" | "chore";

  function suggestCommitType(
    files: Array<{ status: string; category: FileCategory }>,
  ): CommitType {
    const categories = new Set(files.map((f) => f.category));
    const statuses = new Set(files.map((f) => f.status));
    if (categories.size === 1 && categories.has("docs")) return "docs";
    if (categories.size === 1 && categories.has("test")) return "test";
    if (categories.size === 1 && categories.has("config")) return "chore";
    if (statuses.has("A") && !statuses.has("D")) return "feat";
    if (statuses.has("R")) return "refactor";
    const sourceFiles = files.filter((f) => f.category === "source");
    if (sourceFiles.length > 0 && sourceFiles.length <= 3) return "fix";
    return "feat";
  }

  pi.registerTool({
    name: "git_diff_summary",
    label: "Git Diff Summary",
    description:
      "Returns a structured summary of git changes: files changed, insertions/deletions, auto-categorization (source/test/config/docs/migration), and suggested commit type.",
    parameters: Type.Object({
      base: Type.Optional(
        Type.String({
          description:
            "Base ref (default: HEAD for uncommitted, or main for branch comparison)",
        }),
      ),
      target: Type.Optional(Type.String({ description: "Target ref (default: working tree)" })),
      includeStaged: Type.Optional(
        Type.Boolean({ description: "Include staged changes (default: true)" }),
      ),
    }),
    async execute(_toolCallId, args, _signal, _onUpdate, ctx) {
      const cwd = ctx.cwd;

      function buildDiffArgs(formatFlag: string): string[] {
        if (args.base && args.target) {
          return ["diff", formatFlag, args.base, args.target];
        } else if (args.base) {
          return ["diff", formatFlag, args.base];
        } else if (args.includeStaged !== false) {
          return ["diff", formatFlag, "HEAD"];
        } else {
          return ["diff", formatFlag];
        }
      }

      const [numstatResult, nameStatusResult] = await Promise.all([
        exec("git", buildDiffArgs("--numstat"), { cwd }),
        exec("git", buildDiffArgs("--name-status"), { cwd }),
      ]);

      const numstatOut = numstatResult.stdout;
      const nameStatusOut = nameStatusResult.stdout;

      if (!numstatOut.trim() && !nameStatusOut.trim()) {
        return {
          content: [{ type: "text", text: JSON.stringify(
            {
              message: "No changes found.",
              files: [],
              summary: { totalFiles: 0, insertions: 0, deletions: 0, categories: {} },
            },
            null,
            2,
          ) }],
          details: {},
        };
      }

      // Parse --numstat
      const numstatMap = new Map<string, { insertions: number; deletions: number }>();
      for (const line of numstatOut.trim().split("\n").filter(Boolean)) {
        const [add, del, ...pathParts] = line.split("\t");
        const filepath = pathParts.join("\t");
        numstatMap.set(filepath, {
          insertions: add === "-" ? 0 : parseInt(add!, 10) || 0,
          deletions: del === "-" ? 0 : parseInt(del!, 10) || 0,
        });
      }

      // Parse --name-status
      const files: Array<{
        file: string;
        status: string;
        category: FileCategory;
        insertions: number;
        deletions: number;
      }> = [];

      for (const line of nameStatusOut.trim().split("\n").filter(Boolean)) {
        const parts = line.split("\t");
        const status = parts[0]![0]!;
        const filepath = parts.length > 2 ? parts[2]! : parts[1]!;
        const stats =
          numstatMap.get(filepath) ||
          numstatMap.get(parts[1]!) ||
          { insertions: 0, deletions: 0 };

        files.push({
          file: filepath,
          status,
          category: categorize(filepath),
          insertions: stats.insertions,
          deletions: stats.deletions,
        });
      }

      const totalInsertions = files.reduce((a, f) => a + f.insertions, 0);
      const totalDeletions = files.reduce((a, f) => a + f.deletions, 0);
      const categoryBreakdown: Record<string, number> = {};
      for (const f of files) {
        categoryBreakdown[f.category] = (categoryBreakdown[f.category] || 0) + 1;
      }

      return {
        content: [{ type: "text", text: JSON.stringify(
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
        ) }],
        details: {},
      };
    },
  });

  // =========================================================================
  // 4. stack_trace_resolve
  // =========================================================================

  const STRIP_PREFIXES = [
    "/app/",
    "/src/",
    "/home/runner/work/",
    "/home/user/",
    "/var/task/",
    "/opt/app/",
    "/workspace/",
    "/build/",
  ];

  function isInternalFrame(filepath: string): boolean {
    return (
      /node_modules/.test(filepath) ||
      /\/usr\/lib\//.test(filepath) ||
      /\/usr\/local\/lib\//.test(filepath) ||
      /\/lib\/python[\d.]+\//.test(filepath) ||
      /\/go\/pkg\//.test(filepath) ||
      /\/go\/src\//.test(filepath) ||
      /\.cargo\/registry/.test(filepath) ||
      filepath.startsWith("<") ||
      filepath.startsWith("node:") ||
      filepath === "native" ||
      filepath === "internal"
    );
  }

  type StackFormat = "nodejs" | "python" | "go" | "ruby" | "java" | "unknown";

  function detectFormat(trace: string): StackFormat {
    // Check Java/Kotlin/Scala before Node.js — both use "at" but Java has
    // the distinctive .java:NN) / .kt:NN) / .scala:NN) pattern.
    if (/\.(java|kt|scala):\d+\)/.test(trace)) return "java";
    // Use m flag so ^ matches each line (traces start with the error message)
    if (/^\s+at\s+/m.test(trace)) return "nodejs";
    if (/File ".*", line \d+/.test(trace)) return "python";
    if (/\.go:\d+\s/.test(trace)) return "go";
    if (/\.rb:\d+:in\s/.test(trace)) return "ruby";
    return "unknown";
  }

  interface FramePartial {
    function?: string;
    file?: string;
    line?: number;
    column?: number;
  }

  // Parsers use \s* (not \s+) because lines are trimmed before parsing
  function parseNodejs(line: string): FramePartial | null {
    const match =
      line.match(/^\s*at\s+(.+?)\s+\((.+?):(\d+):(\d+)\)/) ||
      line.match(/^\s*at\s+()(.+?):(\d+):(\d+)/);
    if (!match) return null;
    return {
      function: match[1] || undefined,
      file: match[2],
      line: parseInt(match[3]!, 10),
      column: parseInt(match[4]!, 10),
    };
  }

  function parsePython(line: string): FramePartial | null {
    const match = line.match(/File "(.+?)", line (\d+)(?:, in (.+))?/);
    if (!match) return null;
    return {
      file: match[1],
      line: parseInt(match[2]!, 10),
      function: match[3] || undefined,
    };
  }

  function parseGo(line: string): FramePartial | null {
    const match = line.match(/\t?(.+\.go):(\d+)/);
    if (!match) return null;
    return { file: match[1], line: parseInt(match[2]!, 10) };
  }

  function parseRuby(line: string): FramePartial | null {
    const match = line.match(/(.+?):(\d+):in\s+[`'](.+?)'/);
    if (!match) return null;
    return {
      file: match[1],
      line: parseInt(match[2]!, 10),
      function: match[3],
    };
  }

  function parseJava(line: string): FramePartial | null {
    const match = line.match(/at\s+(.+?)\((.+?):(\d+)\)/);
    if (!match) return null;
    return {
      function: match[1],
      file: match[2],
      line: parseInt(match[3]!, 10),
    };
  }

  pi.registerTool({
    name: "stack_trace_resolve",
    label: "Stack Trace Resolve",
    description:
      "Takes a raw stack trace and resolves each frame to the actual source file and line in the current workspace. Handles compiled output paths and container path mappings.",
    parameters: Type.Object({
      stackTrace: Type.String({
        description: "Raw stack trace text (paste the whole thing)",
      }),
      sourceMapDir: Type.Optional(
        Type.String({
          description: "Directory containing .map files (default: auto-detect)",
        }),
      ),
    }),
    async execute(_toolCallId, args, _signal, _onUpdate, ctx) {
      const { existsSync } = await import("fs");
      const { join, basename } = await import("path");

      const worktree = ctx.cwd;
      const traceLines = args.stackTrace.split("\n");
      const format = detectFormat(args.stackTrace);

      function resolveToWorkspace(filepath: string): string | undefined {
        if (existsSync(join(worktree, filepath))) return filepath;
        for (const prefix of STRIP_PREFIXES) {
          if (filepath.startsWith(prefix)) {
            const relative = filepath.slice(prefix.length);
            if (existsSync(join(worktree, relative))) return relative;
          }
        }
        return undefined;
      }

      const parsers: Record<StackFormat, (line: string) => FramePartial | null> = {
        nodejs: parseNodejs,
        python: parsePython,
        go: parseGo,
        ruby: parseRuby,
        java: parseJava,
        unknown: () => null,
      };

      const parser = parsers[format];

      interface Frame {
        original: string;
        file?: string;
        resolvedFile?: string;
        line?: number;
        column?: number;
        function?: string;
        isInternal: boolean;
      }

      const frames: Frame[] = [];
      let entryFrame: number | null = null;

      for (const line of traceLines) {
        const trimmed = line.trim();
        if (!trimmed) continue;

        const parsed = parser(trimmed);
        if (!parsed || !parsed.file) continue;

        const isInternal = isInternalFrame(parsed.file);
        const resolvedFile = isInternal ? undefined : resolveToWorkspace(parsed.file);

        const frame: Frame = {
          original: trimmed,
          file: parsed.file,
          resolvedFile: resolvedFile || undefined,
          line: parsed.line,
          column: parsed.column,
          function: parsed.function,
          isInternal,
        };

        if (entryFrame === null && !isInternal && resolvedFile) {
          entryFrame = frames.length;
        }

        frames.push(frame);
      }

      if (frames.length === 0) {
        return {
          content: [{ type: "text", text: JSON.stringify(
            {
              format: "unknown",
              frames: [],
              note: "Could not parse any stack frames from the input. Supported formats: Node.js, Python, Go, Ruby, Java.",
              raw: args.stackTrace.slice(0, 1000),
            },
            null,
            2,
          ) }],
          details: {},
        };
      }

      const relatedFiles = [
        ...new Set(frames.filter((f) => f.resolvedFile).map((f) => f.resolvedFile!)),
      ];

      return {
        content: [{ type: "text", text: JSON.stringify({ format, entryFrame, relatedFiles, frames }, null, 2) }],
        details: {},
      };
    },
  });

  // =========================================================================
  // 5. test_run_parsed
  // =========================================================================

  type Framework = "jest" | "vitest" | "pytest" | "go" | "rspec" | "unknown";

  function detectFramework(command: string): Framework {
    const trimmed = command.trim();

    // Detect task runner commands by looking at the task name
    // These need to match common task names in Taskfile.yml
    if (/^task test/.test(trimmed)) return "vitest";  // pi-minions uses vitest
    if (/^task jest/.test(trimmed)) return "jest";
    if (/^task pytest/.test(trimmed)) return "pytest";
    if (/^task rspec/.test(trimmed)) return "rspec";

    // Direct framework commands
    if (/\bvitest\b/.test(command)) return "vitest";
    if (/\bjest\b/.test(command) || /\breact-scripts test\b/.test(command)) return "jest";
    if (/\bpytest\b/.test(command)) return "pytest";
    if (/\bgo test\b/.test(command)) return "go";
    if (/\brspec\b/.test(command)) return "rspec";
    return "unknown";
  }

  function appendJsonFlag(command: string, framework: Framework): string {
    // Check if using task runner
    const isTask = command.trim().startsWith("task ");

    switch (framework) {
      case "jest":
        return isTask ? `${command} json=true` : `${command} --json`;
      case "vitest":
        // Use json=true variable for task, --reporter=json for direct vitest
        return isTask ? `${command} json=true` : `${command} --reporter=json`;
      case "go":
        if (isTask) {
          return `${command} -- -json`;
        }
        return command.replace("go test", "go test -json");
      case "rspec":
        return isTask ? `${command} json=true` : `${command} --format json`;
      case "pytest":
        return isTask ? `${command} -- -q --tb=short` : `${command} -q --tb=short`;
      default:
        return command;
    }
  }

  interface TestResult {
    summary: { passed: number; failed: number; skipped: number; duration?: string; note?: string };
    failures: Array<{
      testName: string;
      file?: string;
      line?: number;
      error: string;
      expected?: string;
      actual?: string;
    }>;
    raw?: string;
    note?: string;
    error?: string;
  }

  function parseJestJson(raw: string): TestResult | null {
    try {
      const data = JSON.parse(raw);
      // Jest format: data.testResults[] with assertionResults[]
      const failures = (data.testResults || []).flatMap(
        (suite: {
          testFilePath?: string;
          assertionResults?: Array<{
            status: string;
            fullName: string;
            failureMessages?: string[];
          }>;
        }) =>
          (suite.assertionResults || [])
            .filter((t: { status: string }) => t.status === "failed")
            .map((t: { fullName: string; failureMessages?: string[] }) => ({
              testName: t.fullName,
              file: suite.testFilePath,
              error: (t.failureMessages || []).join("\n").slice(0, 500),
            })),
      );
      return {
        summary: {
          passed: data.numPassedTests || 0,
          failed: data.numFailedTests || 0,
          skipped: data.numPendingTests || 0,
          duration: data.testResults
            ? `${(
                (
                  data.testResults as Array<{ perfStats?: { runtime?: number } }>
                ).reduce(
                  (a: number, r: { perfStats?: { runtime?: number } }) =>
                    a + (r.perfStats?.runtime || 0),
                  0,
                ) / 1000
              ).toFixed(1)}s`
            : undefined,
        },
        failures,
      };
    } catch {
      return null;
    }
  }

  function parseVitestJson(raw: string): TestResult | null {
    try {
      const data = JSON.parse(raw);
      // Vitest uses Jest-compatible format: testResults[].assertionResults[]
      const failures: TestResult["failures"] = [];

      for (const result of data.testResults || []) {
        const testFilePath = result.name;

        for (const test of result.assertionResults || []) {
          if (test.status === "failed") {
            failures.push({
              testName: test.fullName || test.title || "unnamed test",
              file: testFilePath,
              line: test.line,
              error: (test.failureMessages || []).join("\n").slice(0, 500),
            });
          }
        }
      }

      return {
        summary: {
          passed: data.numPassedTests || 0,
          failed: data.numFailedTests || 0,
          skipped: data.numPendingTests || 0,
        },
        failures,
      };
    } catch {
      return null;
    }
  }

  function parseGoTest(raw: string): TestResult | null {
    try {
      const lines = raw
        .trim()
        .split("\n")
        .map((l) => {
          try {
            return JSON.parse(l);
          } catch {
            return null;
          }
        })
        .filter(Boolean);

      if (lines.length === 0) return null;

      let passed = 0;
      let failed = 0;
      let skipped = 0;
      const failures: TestResult["failures"] = [];

      for (const ev of lines) {
        if (ev.Action === "pass" && ev.Test) passed++;
        if (ev.Action === "skip" && ev.Test) skipped++;
        if (ev.Action === "fail" && ev.Test) {
          failed++;
          failures.push({
            testName: ev.Test,
            file: ev.Package,
            error: ev.Output?.slice(0, 500) || "Test failed",
          });
        }
      }

      return { summary: { passed, failed, skipped }, failures };
    } catch {
      return null;
    }
  }

  function truncateRaw(raw: string): string {
    const lines = raw.split("\n");
    if (lines.length <= RAW_OUTPUT_MAX_LINES) return raw;
    return (
      `[...truncated ${lines.length - RAW_OUTPUT_MAX_LINES} lines...]\n` +
      lines.slice(-RAW_OUTPUT_MAX_LINES).join("\n")
    );
  }

  pi.registerTool({
    name: "test_run_parsed",
    label: "Test Run Parsed",
    description:
      "Run tests and return structured results (pass/fail per test, failure messages, stack traces with file locations). Auto-detects test framework from the command.",
    parameters: Type.Object({
      command: Type.String({
        description:
          "Test command to run, e.g. 'npm test', 'pytest tests/', 'go test ./...'",
      }),
      filter: Type.Optional(
        Type.String({ description: "Test name filter pattern" }),
      ),
    }),
    async execute(_toolCallId, args, _signal, _onUpdate, ctx) {
      const framework = detectFramework(args.command);
      let command = args.command;

      if (args.filter) {
        switch (framework) {
          case "jest":
          case "vitest":
            command = `${command} -t "${args.filter}"`;
            break;
          case "pytest":
            command = `${command} -k "${args.filter}"`;
            break;
          case "go":
            command = `${command} -run "${args.filter}"`;
            break;
          case "rspec":
            command = `${command} -e "${args.filter}"`;
            break;
        }
      }

      const jsonCommand = appendJsonFlag(command, framework);

      try {
        const { stdout, stderr } = await execShell(jsonCommand, {
          cwd: ctx.cwd,
          timeout: TEST_TIMEOUT_MS,
        });

        let result: TestResult | null = null;

        if (framework === "jest") {
          result = parseJestJson(stdout);
        } else if (framework === "vitest") {
          result = parseVitestJson(stdout);
        } else if (framework === "go") {
          result = parseGoTest(stdout);
        } else if (framework === "rspec") {
          try {
            const data = JSON.parse(stdout);
            result = {
              summary: {
                passed:
                  data.summary?.example_count -
                  (data.summary?.failure_count || 0) -
                  (data.summary?.pending_count || 0),
                failed: data.summary?.failure_count || 0,
                skipped: data.summary?.pending_count || 0,
                duration: data.summary?.duration
                  ? `${data.summary.duration.toFixed(1)}s`
                  : undefined,
              },
              failures: (data.examples || [])
                .filter((e: { status: string }) => e.status === "failed")
                .map(
                  (e: {
                    full_description: string;
                    file_path?: string;
                    line_number?: number;
                    exception?: { message?: string };
                  }) => ({
                    testName: e.full_description,
                    file: e.file_path,
                    line: e.line_number,
                    error: e.exception?.message?.slice(0, 500) || "Test failed",
                  }),
                ),
            };
          } catch {
            result = null;
          }
        }

        // Fallback: raw output if structured parsing failed
        if (!result) {
          const combined = stdout + (stderr ? `\n--- stderr ---\n${stderr}` : "");
          return {
            content: [{ type: "text", text: JSON.stringify(
              {
                summary: {
                  passed: 0,
                  failed: 0,
                  skipped: 0,
                  note: "Could not parse structured results",
                },
                failures: [],
                raw: truncateRaw(combined),
                note: `Framework detected: ${framework}. Structured parsing failed -- raw output returned.`,
              },
              null,
              2,
            ) }],
            details: {},
          };
        }

        return {
          content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
          details: {},
        };
      } catch (e) {
        return {
          content: [{ type: "text", text: JSON.stringify(
            {
              summary: { passed: 0, failed: 0, skipped: 0 },
              failures: [],
              error: (e as Error).message,
              note: "Test command failed to execute.",
            },
            null,
            2,
          ) }],
          details: {},
        };
      }
    },
  });
}
