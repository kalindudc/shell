import { tool } from "@opencode-ai/plugin"

const TIMEOUT_MS = 5 * 60 * 1000 // 5 minutes
const RAW_OUTPUT_MAX_LINES = 200

interface TestResult {
  summary: { passed: number; failed: number; skipped: number; duration?: string }
  failures: Array<{
    testName: string
    file?: string
    line?: number
    error: string
    expected?: string
    actual?: string
  }>
  raw?: string
  note?: string
}

type Framework = "jest" | "vitest" | "pytest" | "go" | "rspec" | "unknown"

function detectFramework(command: string): Framework {
  if (/\bvitest\b/.test(command)) return "vitest"
  if (/\bjest\b/.test(command) || /\breact-scripts test\b/.test(command)) return "jest"
  if (/\bpytest\b/.test(command)) return "pytest"
  if (/\bgo test\b/.test(command)) return "go"
  if (/\brspec\b/.test(command)) return "rspec"
  return "unknown"
}

function appendJsonFlag(command: string, framework: Framework): string {
  switch (framework) {
    case "jest":
      return `${command} --json`
    case "vitest":
      return `${command} --reporter=json`
    case "go":
      return command.replace("go test", "go test -json")
    case "rspec":
      return `${command} --format json`
    case "pytest":
      return `${command} -q --tb=short`
    default:
      return command
  }
}

function parseJestVitest(raw: string): TestResult | null {
  try {
    const data = JSON.parse(raw)
    const failures = (data.testResults || [])
      .flatMap(
        (suite: {
          testFilePath?: string
          assertionResults?: Array<{
            status: string
            fullName: string
            failureMessages?: string[]
          }>
        }) =>
          (suite.assertionResults || [])
            .filter((t: { status: string }) => t.status === "failed")
            .map((t: { fullName: string; failureMessages?: string[] }) => ({
              testName: t.fullName,
              file: suite.testFilePath,
              error: (t.failureMessages || []).join("\n").slice(0, 500),
            })),
      )
    return {
      summary: {
        passed: data.numPassedTests || 0,
        failed: data.numFailedTests || 0,
        skipped: data.numPendingTests || 0,
        duration: data.testResults
          ? `${((data.testResults as Array<{ perfStats?: { runtime?: number } }>).reduce((a: number, r: { perfStats?: { runtime?: number } }) => a + (r.perfStats?.runtime || 0), 0) / 1000).toFixed(1)}s`
          : undefined,
      },
      failures,
    }
  } catch {
    return null
  }
}

function parseGoTest(raw: string): TestResult | null {
  try {
    const lines = raw
      .trim()
      .split("\n")
      .map((l) => {
        try {
          return JSON.parse(l)
        } catch {
          return null
        }
      })
      .filter(Boolean)

    if (lines.length === 0) return null

    let passed = 0
    let failed = 0
    let skipped = 0
    const failures: TestResult["failures"] = []

    for (const ev of lines) {
      if (ev.Action === "pass" && ev.Test) passed++
      if (ev.Action === "skip" && ev.Test) skipped++
      if (ev.Action === "fail" && ev.Test) {
        failed++
        failures.push({
          testName: ev.Test,
          file: ev.Package,
          error: ev.Output?.slice(0, 500) || "Test failed",
        })
      }
    }

    return { summary: { passed, failed, skipped }, failures }
  } catch {
    return null
  }
}

function truncateRaw(raw: string): string {
  const lines = raw.split("\n")
  if (lines.length <= RAW_OUTPUT_MAX_LINES) return raw
  return (
    `[...truncated ${lines.length - RAW_OUTPUT_MAX_LINES} lines...]\n` +
    lines.slice(-RAW_OUTPUT_MAX_LINES).join("\n")
  )
}

export default tool({
  description:
    "Run tests and return structured results (pass/fail per test, failure messages, stack traces with file locations). Auto-detects test framework from the command. Returns parsed JSON instead of raw terminal output.",
  args: {
    command: tool.schema
      .string()
      .describe("Test command to run, e.g. 'npm test', 'pytest tests/', 'go test ./...'"),
    filter: tool.schema
      .string()
      .optional()
      .describe("Test name filter pattern"),
  },
  async execute(args, context) {
    const framework = detectFramework(args.command)
    let command = args.command

    if (args.filter) {
      switch (framework) {
        case "jest":
        case "vitest":
          command = `${command} -t "${args.filter}"`
          break
        case "pytest":
          command = `${command} -k "${args.filter}"`
          break
        case "go":
          command = `${command} -run "${args.filter}"`
          break
        case "rspec":
          command = `${command} -e "${args.filter}"`
          break
      }
    }

    const jsonCommand = appendJsonFlag(command, framework)

    try {
      // Use Bun.spawn with bash -c since the command is a user-provided string
      // that may contain pipes, redirects, etc. that need bash interpretation.
      const proc = Bun.spawn(["bash", "-c", jsonCommand], {
        cwd: context.worktree,
        stdout: "pipe",
        stderr: "pipe",
      })

      const timeoutId = setTimeout(() => proc.kill(), TIMEOUT_MS)
      const stdout = await new Response(proc.stdout).text()
      const stderr = await new Response(proc.stderr).text()
      clearTimeout(timeoutId)

      let result: TestResult | null = null

      if (framework === "jest" || framework === "vitest") {
        result = parseJestVitest(stdout)
      } else if (framework === "go") {
        result = parseGoTest(stdout)
      } else if (framework === "rspec") {
        try {
          const data = JSON.parse(stdout)
          result = {
            summary: {
              passed: data.summary?.example_count - (data.summary?.failure_count || 0) - (data.summary?.pending_count || 0),
              failed: data.summary?.failure_count || 0,
              skipped: data.summary?.pending_count || 0,
              duration: data.summary?.duration ? `${data.summary.duration.toFixed(1)}s` : undefined,
            },
            failures: (data.examples || [])
              .filter((e: { status: string }) => e.status === "failed")
              .map((e: { full_description: string; file_path?: string; line_number?: number; exception?: { message?: string } }) => ({
                testName: e.full_description,
                file: e.file_path,
                line: e.line_number,
                error: e.exception?.message?.slice(0, 500) || "Test failed",
              })),
          }
        } catch {
          result = null
        }
      }

      // Fallback: return raw output if structured parsing failed
      if (!result) {
        const combined = stdout + (stderr ? `\n--- stderr ---\n${stderr}` : "")
        return JSON.stringify(
          {
            summary: { passed: 0, failed: 0, skipped: 0, note: "Could not parse structured results" },
            failures: [],
            raw: truncateRaw(combined),
            note: `Framework detected: ${framework}. Structured parsing failed -- raw output returned.`,
          },
          null,
          2,
        )
      }

      return JSON.stringify(result, null, 2)
    } catch (e) {
      return JSON.stringify(
        {
          summary: { passed: 0, failed: 0, skipped: 0 },
          failures: [],
          error: (e as Error).message,
          note: "Test command failed to execute.",
        },
        null,
        2,
      )
    }
  },
})
