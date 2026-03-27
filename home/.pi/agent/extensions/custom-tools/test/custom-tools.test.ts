/**
 * Unit tests for custom-tools pi extension.
 *
 * Tests every registered tool's execute function, validating:
 *   1. Return shape matches AgentToolResult: { content: [...], details: {} }
 *   2. Content blocks are valid: { type: "text", text: string }
 *   3. Tool-specific logic (parsing, edge cases)
 *
 * Uses bun:test with mocked child_process.spawn so no real commands run.
 */

import { describe, it, expect, beforeEach, mock } from "bun:test";
import { EventEmitter } from "events";

// ---------------------------------------------------------------------------
// Spawn mock — MUST be declared before the extension import
// ---------------------------------------------------------------------------

interface SpawnResult {
  stdout: string;
  stderr: string;
  exitCode: number;
}

/** FIFO queue consumed by each spawn() call. */
let spawnQueue: SpawnResult[] = [];

function setSpawnResults(...results: SpawnResult[]) {
  spawnQueue = [...results];
}

function ok(stdout: string): SpawnResult {
  return { stdout, stderr: "", exitCode: 0 };
}

function fail(stderr: string, exitCode = 1): SpawnResult {
  return { stdout: "", stderr, exitCode };
}

mock.module("child_process", () => ({
  spawn: (_cmd: string, _args: string[], _opts: unknown) => {
    const behavior = spawnQueue.shift() ?? { stdout: "", stderr: "", exitCode: 0 };
    const proc = new EventEmitter() as EventEmitter & { stdout: EventEmitter; stderr: EventEmitter };
    const stdoutEmitter = new EventEmitter();
    const stderrEmitter = new EventEmitter();

    proc.stdout = stdoutEmitter;
    proc.stderr = stderrEmitter;

    queueMicrotask(() => {
      if (behavior.stdout) stdoutEmitter.emit("data", Buffer.from(behavior.stdout));
      if (behavior.stderr) stderrEmitter.emit("data", Buffer.from(behavior.stderr));
      proc.emit("close", behavior.exitCode);
    });

    return proc;
  },
}));

// ---------------------------------------------------------------------------
// Import extension AFTER mock is installed
// ---------------------------------------------------------------------------

import extensionFactory from "../index";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface ContentBlock {
  type: string;
  text?: string;
}

interface ToolResult {
  content: ContentBlock[];
  details: Record<string, unknown>;
}

interface ToolDefinition {
  name: string;
  label: string;
  description: string;
  parameters: unknown;
  execute: (...args: unknown[]) => Promise<ToolResult>;
}

// ---------------------------------------------------------------------------
// Bootstrap — register all tools via mock ExtensionAPI
// ---------------------------------------------------------------------------

const tools = new Map<string, ToolDefinition>();
const mockPi = {
  registerTool(tool: ToolDefinition) {
    tools.set(tool.name, tool);
  },
};

extensionFactory(mockPi as never);

function getTool(name: string): ToolDefinition {
  const tool = tools.get(name);
  if (!tool) throw new Error(`Tool "${name}" not registered`);
  return tool;
}

/** Shorthand to call a tool's execute with default dummy args. */
async function executeTool(
  name: string,
  args: Record<string, unknown>,
  ctx: { cwd: string } = { cwd: "/test/workspace" },
): Promise<ToolResult> {
  const tool = getTool(name);
  return tool.execute("test-call-id", args, undefined, undefined, ctx) as Promise<ToolResult>;
}

// ---------------------------------------------------------------------------
// Validation helpers
// ---------------------------------------------------------------------------

/** Assert the result satisfies the AgentToolResult contract. */
function expectValidResult(result: ToolResult) {
  expect(result).toBeDefined();
  expect(result).not.toBeNull();
  expect(result.content).toBeInstanceOf(Array);
  expect(result.content.length).toBeGreaterThan(0);

  for (const block of result.content) {
    expect(block.type).toBe("text");
    expect(typeof block.text).toBe("string");
    expect(block.text!.length).toBeGreaterThan(0);
  }

  // details MUST be present (AgentToolResult requires it)
  expect(result).toHaveProperty("details");
  expect(result.details).toBeDefined();
}

/** Parse the JSON text inside the first content block. */
function parseResultJson(result: ToolResult): unknown {
  return JSON.parse(result.content[0]!.text!);
}

// ===========================================================================
// Tests
// ===========================================================================

describe("custom-tools extension", () => {
  // -----------------------------------------------------------------------
  // Registration
  // -----------------------------------------------------------------------
  describe("registration", () => {
    it("registers all 5 tools", () => {
      const expected = ["ast_query", "git_blame", "git_diff_summary", "stack_trace_resolve", "test_run_parsed"];
      for (const name of expected) {
        expect(tools.has(name)).toBe(true);
      }
      expect(tools.size).toBe(expected.length);
    });

    it("each tool has required metadata", () => {
      for (const [, tool] of tools) {
        expect(typeof tool.name).toBe("string");
        expect(typeof tool.label).toBe("string");
        expect(typeof tool.description).toBe("string");
        expect(tool.parameters).toBeDefined();
        expect(typeof tool.execute).toBe("function");
      }
    });
  });

  // -----------------------------------------------------------------------
  // ast_query
  // -----------------------------------------------------------------------
  describe("ast_query", () => {
    beforeEach(() => { spawnQueue = []; });

    it("returns matches when sg finds results", async () => {
      const sgOutput = JSON.stringify([
        { file: "src/index.ts", range: { start: { line: 10 } }, text: "catch (e) { }" },
        { file: "src/utils.ts", range: { start: { line: 42 } }, text: "catch (err) { }" },
      ]);
      setSpawnResults(ok(sgOutput));

      const result = await executeTool("ast_query", { pattern: "catch ($ERR) { }", language: "ts" });
      expectValidResult(result);

      const data = parseResultJson(result) as { totalMatches: number; matches: unknown[] };
      expect(data.totalMatches).toBe(2);
      expect(data.matches).toHaveLength(2);
    });

    it("returns no-matches message for empty array", async () => {
      setSpawnResults(ok("[]"));

      const result = await executeTool("ast_query", { pattern: "nonexistent", language: "ts" });
      expectValidResult(result);
      expect(result.content[0]!.text).toBe("No matches found.");
    });

    it("handles sg not installed", async () => {
      setSpawnResults(
        fail("command not found"),   // sg fails
        ok(""),                      // which sg returns empty
      );

      const result = await executeTool("ast_query", { pattern: "test", language: "ts" });
      expectValidResult(result);
      expect(result.content[0]!.text).toContain("not installed");
    });

    it("handles sg error with message", async () => {
      setSpawnResults(
        fail("invalid pattern"),     // sg fails
        ok("/usr/local/bin/sg\n"),   // which sg finds it
      );

      const result = await executeTool("ast_query", { pattern: "bad[", language: "ts" });
      expectValidResult(result);
      expect(result.content[0]!.text).toContain("ast-grep error");
    });

    it("handles non-JSON sg output", async () => {
      setSpawnResults(ok("not valid json at all"));

      const result = await executeTool("ast_query", { pattern: "test", language: "ts" });
      expectValidResult(result);
      expect(result.content[0]!.text).toContain("non-JSON output");
    });

    it("uses provided path instead of cwd", async () => {
      setSpawnResults(ok("[]"));

      const result = await executeTool("ast_query", { pattern: "x", language: "ts", path: "/custom/path" });
      expectValidResult(result);
    });

    it("truncates matches beyond MAX_MATCHES (20)", async () => {
      const manyMatches = Array.from({ length: 25 }, (_, i) => ({
        file: `src/file${i}.ts`,
        range: { start: { line: i } },
        text: `match ${i}`,
      }));
      setSpawnResults(ok(JSON.stringify(manyMatches)));

      const result = await executeTool("ast_query", { pattern: "test", language: "ts" });
      expectValidResult(result);

      const data = parseResultJson(result) as { totalMatches: number; showing: number; note: string };
      expect(data.totalMatches).toBe(25);
      expect(data.showing).toBe(20);
      expect(data.note).toContain("5 additional matches");
    });
  });

  // -----------------------------------------------------------------------
  // git_blame
  // -----------------------------------------------------------------------
  describe("git_blame", () => {
    beforeEach(() => { spawnQueue = []; });

    // 40-char hex SHA — must be exactly 40 for porcelain blame regex
    const MOCK_SHA = "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2";

    const PORCELAIN_BLAME = [
      `${MOCK_SHA} 1 1 1`,
      "author John Doe",
      "author-mail <john@example.com>",
      "author-time 1700000000",
      "author-tz +0000",
      "committer John Doe",
      "committer-mail <john@example.com>",
      "committer-time 1700000000",
      "committer-tz +0000",
      "summary Initial commit (#42)",
      "filename src/main.ts",
      "\tconst x = 1;",
    ].join("\n");

    const GIT_SHOW_OUTPUT = [
      `${MOCK_SHA}\x00John Doe\x00john@example.com\x002024-01-15T10:00:00+00:00\x00Initial commit (#42)`,
      " src/main.ts | 10 ++++++++++",
    ].join("\n");

    it("returns parsed blame with commit info", async () => {
      setSpawnResults(ok(PORCELAIN_BLAME), ok(GIT_SHOW_OUTPUT));

      const result = await executeTool("git_blame", { file: "src/main.ts", startLine: 1, endLine: 1 });
      expectValidResult(result);

      const data = parseResultJson(result) as { lines: unknown[]; commits: Array<{ author: string; prNumber?: string }> };
      expect(data.lines).toHaveLength(1);
      expect(data.commits).toHaveLength(1);
      expect(data.commits[0]!.author).toBe("John Doe");
      expect(data.commits[0]!.prNumber).toBe("42");
    });

    it("returns error for empty blame output", async () => {
      setSpawnResults(ok(""));

      const result = await executeTool("git_blame", { file: "nonexistent.ts", startLine: 1, endLine: 1 });
      expectValidResult(result);

      const data = parseResultJson(result) as { error: string };
      expect(data.error).toContain("No blame data");
    });

    it("handles unparseable blame output", async () => {
      setSpawnResults(ok("garbage output with no commit hashes"));

      const result = await executeTool("git_blame", { file: "test.ts", startLine: 1, endLine: 1 });
      expectValidResult(result);

      const data = parseResultJson(result) as { error: string };
      expect(data.error).toContain("Could not parse");
    });
  });

  // -----------------------------------------------------------------------
  // git_diff_summary
  // -----------------------------------------------------------------------
  describe("git_diff_summary", () => {
    beforeEach(() => { spawnQueue = []; });

    it("returns structured diff with file categorization", async () => {
      const numstat = "10\t2\tsrc/main.ts\n5\t0\ttest/main.test.ts\n1\t1\tREADME.md\n";
      const nameStatus = "M\tsrc/main.ts\nA\ttest/main.test.ts\nM\tREADME.md\n";
      setSpawnResults(ok(numstat), ok(nameStatus));

      const result = await executeTool("git_diff_summary", {});
      expectValidResult(result);

      const data = parseResultJson(result) as {
        summary: { totalFiles: number; insertions: number; deletions: number; categories: Record<string, number> };
        files: Array<{ category: string }>;
      };
      expect(data.summary.totalFiles).toBe(3);
      expect(data.summary.insertions).toBe(16);
      expect(data.summary.deletions).toBe(3);
      expect(data.summary.categories.source).toBe(1);
      expect(data.summary.categories.test).toBe(1);
      expect(data.summary.categories.docs).toBe(1);
    });

    it("returns no-changes message for empty diff", async () => {
      setSpawnResults(ok(""), ok(""));

      const result = await executeTool("git_diff_summary", {});
      expectValidResult(result);

      const data = parseResultJson(result) as { message: string };
      expect(data.message).toBe("No changes found.");
    });

    it("categorizes config files correctly", async () => {
      const numstat = "1\t0\tpackage.json\n2\t0\tDockerfile\n3\t0\tyarn.lock\n";
      const nameStatus = "M\tpackage.json\nA\tDockerfile\nM\tyarn.lock\n";
      setSpawnResults(ok(numstat), ok(nameStatus));

      const result = await executeTool("git_diff_summary", {});
      expectValidResult(result);

      const data = parseResultJson(result) as { summary: { categories: Record<string, number>; suggestedCommitType: string } };
      expect(data.summary.categories.config).toBe(3);
      expect(data.summary.suggestedCommitType).toBe("chore");
    });

    it("suggests 'docs' commit type for docs-only changes", async () => {
      const numstat = "5\t0\tdocs/guide.md\n";
      const nameStatus = "A\tdocs/guide.md\n";
      setSpawnResults(ok(numstat), ok(nameStatus));

      const result = await executeTool("git_diff_summary", {});
      expectValidResult(result);

      const data = parseResultJson(result) as { summary: { suggestedCommitType: string } };
      expect(data.summary.suggestedCommitType).toBe("docs");
    });

    it("categorizes migration files", async () => {
      const numstat = "20\t0\tdb/migrations/001_create_users.sql\n";
      const nameStatus = "A\tdb/migrations/001_create_users.sql\n";
      setSpawnResults(ok(numstat), ok(nameStatus));

      const result = await executeTool("git_diff_summary", {});
      expectValidResult(result);

      const data = parseResultJson(result) as { files: Array<{ category: string }> };
      expect(data.files[0]!.category).toBe("migration");
    });

    it("categorizes generated files", async () => {
      const numstat = "100\t0\tsrc/generated/schema.gen.ts\n";
      const nameStatus = "M\tsrc/generated/schema.gen.ts\n";
      setSpawnResults(ok(numstat), ok(nameStatus));

      const result = await executeTool("git_diff_summary", {});
      expectValidResult(result);

      const data = parseResultJson(result) as { files: Array<{ category: string }> };
      expect(data.files[0]!.category).toBe("generated");
    });
  });

  // -----------------------------------------------------------------------
  // stack_trace_resolve
  // -----------------------------------------------------------------------
  describe("stack_trace_resolve", () => {
    it("parses Node.js stack traces", async () => {
      const trace = [
        "TypeError: Cannot read property 'foo' of undefined",
        "    at Object.bar (/app/src/utils.ts:42:10)",
        "    at main (/app/src/index.ts:10:5)",
        "    at Module._compile (node:internal/modules/cjs/loader:1254:14)",
      ].join("\n");

      const result = await executeTool("stack_trace_resolve", { stackTrace: trace });
      expectValidResult(result);

      const data = parseResultJson(result) as { format: string; frames: Array<{ file: string; line: number; isInternal: boolean }> };
      expect(data.format).toBe("nodejs");
      expect(data.frames).toHaveLength(3);
      expect(data.frames[0]!.file).toBe("/app/src/utils.ts");
      expect(data.frames[0]!.line).toBe(42);
      expect(data.frames[2]!.isInternal).toBe(true);
    });

    it("parses Python stack traces", async () => {
      const trace = [
        'Traceback (most recent call last):',
        '  File "/app/main.py", line 10, in main',
        '    result = process(data)',
        '  File "/app/utils.py", line 25, in process',
        '    return data["key"]',
        'KeyError: "key"',
      ].join("\n");

      const result = await executeTool("stack_trace_resolve", { stackTrace: trace });
      expectValidResult(result);

      const data = parseResultJson(result) as { format: string; frames: Array<{ file: string; function?: string }> };
      expect(data.format).toBe("python");
      expect(data.frames).toHaveLength(2);
      expect(data.frames[0]!.function).toBe("main");
    });

    it("parses Go stack traces", async () => {
      const trace = [
        "goroutine 1 [running]:",
        "main.handler()",
        "\t/app/main.go:42 +0x1a4",
        "net/http.HandlerFunc.ServeHTTP()",
        "\t/usr/local/go/src/net/http/server.go:2136 +0x44",
      ].join("\n");

      const result = await executeTool("stack_trace_resolve", { stackTrace: trace });
      expectValidResult(result);

      const data = parseResultJson(result) as { format: string; frames: Array<{ file: string; isInternal: boolean }> };
      expect(data.format).toBe("go");
      expect(data.frames.length).toBeGreaterThanOrEqual(1);
    });

    it("parses Ruby stack traces", async () => {
      const trace = [
        "/app/lib/parser.rb:15:in 'parse'",
        "/app/lib/main.rb:8:in 'run'",
        "/usr/lib/ruby/3.0.0/irb.rb:100:in 'start'",
      ].join("\n");

      const result = await executeTool("stack_trace_resolve", { stackTrace: trace });
      expectValidResult(result);

      const data = parseResultJson(result) as { format: string; frames: Array<{ function?: string; isInternal: boolean }> };
      expect(data.format).toBe("ruby");
      expect(data.frames).toHaveLength(3);
      expect(data.frames[0]!.function).toBe("parse");
      expect(data.frames[2]!.isInternal).toBe(true);
    });

    it("parses Java stack traces", async () => {
      const trace = [
        "java.lang.NullPointerException",
        "\tat com.app.Service.process(Service.java:42)",
        "\tat com.app.Main.main(Main.java:10)",
      ].join("\n");

      const result = await executeTool("stack_trace_resolve", { stackTrace: trace });
      expectValidResult(result);

      const data = parseResultJson(result) as { format: string; frames: Array<{ file: string }> };
      expect(data.format).toBe("java");
      expect(data.frames).toHaveLength(2);
      expect(data.frames[0]!.file).toBe("Service.java");
    });

    it("returns unknown format for unparseable input", async () => {
      const result = await executeTool("stack_trace_resolve", { stackTrace: "just some random text\nno stack frames here" });
      expectValidResult(result);

      const data = parseResultJson(result) as { format: string; frames: unknown[]; note: string };
      expect(data.format).toBe("unknown");
      expect(data.frames).toHaveLength(0);
      expect(data.note).toContain("Could not parse");
    });

    it("identifies internal frames (node_modules, stdlib)", async () => {
      const trace = [
        "    at myFunc (/app/src/index.ts:5:10)",
        "    at Object.require (node_modules/express/lib/router.js:100:5)",
      ].join("\n");

      const result = await executeTool("stack_trace_resolve", { stackTrace: trace });
      expectValidResult(result);

      const data = parseResultJson(result) as { frames: Array<{ isInternal: boolean; file: string }> };
      expect(data.frames[0]!.isInternal).toBe(false);
      expect(data.frames[1]!.isInternal).toBe(true);
    });
  });

  // -----------------------------------------------------------------------
  // test_run_parsed
  // -----------------------------------------------------------------------
  describe("test_run_parsed", () => {
    beforeEach(() => { spawnQueue = []; });

    it("parses jest JSON output (all passing)", async () => {
      const jestOutput = JSON.stringify({
        numPassedTests: 5,
        numFailedTests: 0,
        numPendingTests: 1,
        testResults: [
          { testFilePath: "src/app.test.ts", perfStats: { runtime: 1200 }, assertionResults: [] },
        ],
      });
      setSpawnResults(ok(jestOutput));

      const result = await executeTool("test_run_parsed", { command: "npx jest" });
      expectValidResult(result);

      const data = parseResultJson(result) as { summary: { passed: number; failed: number; skipped: number } };
      expect(data.summary.passed).toBe(5);
      expect(data.summary.failed).toBe(0);
      expect(data.summary.skipped).toBe(1);
    });

    it("parses jest output with failures", async () => {
      const jestOutput = JSON.stringify({
        numPassedTests: 3,
        numFailedTests: 1,
        numPendingTests: 0,
        testResults: [{
          testFilePath: "src/math.test.ts",
          perfStats: { runtime: 500 },
          assertionResults: [{
            status: "failed",
            fullName: "add should sum two numbers",
            failureMessages: ["Expected 4 but got 5"],
          }],
        }],
      });
      setSpawnResults(ok(jestOutput));

      const result = await executeTool("test_run_parsed", { command: "npx jest" });
      expectValidResult(result);

      const data = parseResultJson(result) as { summary: { failed: number }; failures: Array<{ testName: string; error: string }> };
      expect(data.summary.failed).toBe(1);
      expect(data.failures).toHaveLength(1);
      expect(data.failures[0]!.testName).toBe("add should sum two numbers");
    });

    it("parses go test JSON output", async () => {
      const goOutput = [
        '{"Action":"pass","Test":"TestAdd","Package":"./math"}',
        '{"Action":"pass","Test":"TestSub","Package":"./math"}',
        '{"Action":"fail","Test":"TestDiv","Package":"./math","Output":"division by zero"}',
        '{"Action":"skip","Test":"TestMul","Package":"./math"}',
      ].join("\n");
      setSpawnResults(ok(goOutput));

      const result = await executeTool("test_run_parsed", { command: "go test ./..." });
      expectValidResult(result);

      const data = parseResultJson(result) as { summary: { passed: number; failed: number; skipped: number } };
      expect(data.summary.passed).toBe(2);
      expect(data.summary.failed).toBe(1);
      expect(data.summary.skipped).toBe(1);
    });

    it("parses rspec JSON output", async () => {
      const rspecOutput = JSON.stringify({
        summary: { example_count: 10, failure_count: 1, pending_count: 2, duration: 3.456 },
        examples: [
          { full_description: "User#name returns name", status: "passed" },
          {
            full_description: "User#email validates format",
            status: "failed",
            file_path: "./spec/user_spec.rb",
            line_number: 25,
            exception: { message: "expected valid? to be true" },
          },
        ],
      });
      setSpawnResults(ok(rspecOutput));

      const result = await executeTool("test_run_parsed", { command: "bundle exec rspec" });
      expectValidResult(result);

      const data = parseResultJson(result) as { summary: { passed: number; failed: number; duration: string }; failures: Array<{ file: string }> };
      expect(data.summary.passed).toBe(7);
      expect(data.summary.failed).toBe(1);
      expect(data.summary.duration).toBe("3.5s");
      expect(data.failures[0]!.file).toBe("./spec/user_spec.rb");
    });

    it("falls back to raw output for unparseable results", async () => {
      setSpawnResults(ok("PASS: 3 tests\nFAIL: 1 test\nsome other output"));

      const result = await executeTool("test_run_parsed", { command: "pytest tests/" });
      expectValidResult(result);

      const data = parseResultJson(result) as { note: string; raw: string };
      expect(data.note).toContain("Structured parsing failed");
      expect(data.raw).toContain("PASS: 3 tests");
    });

    it("applies test name filter for jest", async () => {
      const jestOutput = JSON.stringify({
        numPassedTests: 1,
        numFailedTests: 0,
        numPendingTests: 0,
        testResults: [],
      });
      setSpawnResults(ok(jestOutput));

      const result = await executeTool("test_run_parsed", {
        command: "npx jest",
        filter: "my test pattern",
      });
      expectValidResult(result);
    });
  });

  // -----------------------------------------------------------------------
  // Cross-cutting: return format validation
  // -----------------------------------------------------------------------
  describe("return format contract", () => {
    beforeEach(() => { spawnQueue = []; });

    it("ast_query: every code path returns { content, details }", async () => {
      // Path 1: sg not installed
      setSpawnResults(fail("not found"), ok(""));
      expectValidResult(await executeTool("ast_query", { pattern: "x", language: "ts" }));

      // Path 2: sg error
      setSpawnResults(fail("bad pattern"), ok("/usr/bin/sg\n"));
      expectValidResult(await executeTool("ast_query", { pattern: "x", language: "ts" }));

      // Path 3: non-JSON output
      setSpawnResults(ok("not json"));
      expectValidResult(await executeTool("ast_query", { pattern: "x", language: "ts" }));

      // Path 4: empty matches
      setSpawnResults(ok("[]"));
      expectValidResult(await executeTool("ast_query", { pattern: "x", language: "ts" }));

      // Path 5: with matches
      setSpawnResults(ok(JSON.stringify([{ file: "a.ts", range: { start: { line: 1 } }, text: "x" }])));
      expectValidResult(await executeTool("ast_query", { pattern: "x", language: "ts" }));
    });

    it("git_blame: every code path returns { content, details }", async () => {
      // Path 1: empty blame
      setSpawnResults(ok(""));
      expectValidResult(await executeTool("git_blame", { file: "x.ts", startLine: 1, endLine: 1 }));

      // Path 2: unparseable blame
      setSpawnResults(ok("garbage"));
      expectValidResult(await executeTool("git_blame", { file: "x.ts", startLine: 1, endLine: 1 }));
    });

    it("git_diff_summary: every code path returns { content, details }", async () => {
      // Path 1: no changes
      setSpawnResults(ok(""), ok(""));
      expectValidResult(await executeTool("git_diff_summary", {}));

      // Path 2: with changes
      setSpawnResults(ok("1\t0\ta.ts\n"), ok("M\ta.ts\n"));
      expectValidResult(await executeTool("git_diff_summary", {}));
    });

    it("stack_trace_resolve: every code path returns { content, details }", async () => {
      // Path 1: no parseable frames
      expectValidResult(await executeTool("stack_trace_resolve", { stackTrace: "no frames" }));

      // Path 2: with frames
      expectValidResult(await executeTool("stack_trace_resolve", {
        stackTrace: "    at foo (/app/bar.ts:1:1)",
      }));
    });

    it("test_run_parsed: every code path returns { content, details }", async () => {
      // Path 1: successful parse
      setSpawnResults(ok(JSON.stringify({ numPassedTests: 1, numFailedTests: 0, numPendingTests: 0, testResults: [] })));
      expectValidResult(await executeTool("test_run_parsed", { command: "npx jest" }));

      // Path 2: parse failure (raw fallback)
      setSpawnResults(ok("raw output"));
      expectValidResult(await executeTool("test_run_parsed", { command: "pytest tests/" }));
    });
  });
});
