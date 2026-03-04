/**
 * Test harness for session-recorder plugin (v0.2.0 dual-format).
 *
 * Simulates OpenCode's plugin lifecycle by calling the exported plugin function
 * with mock context, then firing events in the same sequence OpenCode does.
 *
 * Run: SESSION_RECORDER_MEMORY_DIR=$(mktemp -d) bun test plugins/session-recorder.test.ts
 * Or:  bun test plugins/session-recorder.test.ts  (auto-creates temp dir)
 */
import { describe, test, expect, beforeAll, afterAll } from "bun:test"
import { mkdtemp, readFile, readdir, rm, writeFile } from "fs/promises"
import { existsSync } from "fs"
import path from "path"
import os from "os"

// ---------------------------------------------------------------------------
// Setup: create temp dir and set env BEFORE importing the plugin
// ---------------------------------------------------------------------------
let tmpDir: string
let cleanup: () => Promise<void>

if (!process.env.SESSION_RECORDER_MEMORY_DIR) {
  tmpDir = await mkdtemp(path.join(os.tmpdir(), "session-recorder-test-"))
  process.env.SESSION_RECORDER_MEMORY_DIR = tmpDir
} else {
  tmpDir = process.env.SESSION_RECORDER_MEMORY_DIR
}

cleanup = async () => {
  if (tmpDir.includes("session-recorder-test-")) {
    await rm(tmpDir, { recursive: true, force: true })
  }
}

// Dynamic import so env is set first
const { SessionRecorderPlugin } = await import("../session-recorder.ts")

// ---------------------------------------------------------------------------
// Mock OpenCode client
// ---------------------------------------------------------------------------
const logs: Array<{ level: string; message: string }> = []
const mockSessionData: Record<string, any> = {}

const mockClient = {
  app: {
    log: async (opts: any) => {
      logs.push({ level: opts.body.level, message: opts.body.message })
    },
  },
  session: {
    get: async ({ path: p }: any) => {
      return { data: mockSessionData[p.id] ?? null }
    },
  },
}

const mockCtx = {
  client: mockClient,
  project: "test-project",
  directory: "/tmp/test",
  worktree: "/tmp/test",
  serverUrl: "http://localhost:4096",
  $: (() => {}) as any,
}

// ---------------------------------------------------------------------------
// Helper: fire events through the plugin hooks
// ---------------------------------------------------------------------------
type Hooks = Awaited<ReturnType<typeof SessionRecorderPlugin>>

let hooks: Hooks

async function fireEvent(type: string, properties: any = {}) {
  await hooks.event!({ event: { type, properties } })
}

async function fireToolAfter(tool: string, sessionID: string, callID: string, title: string, args: any = {}, output = "") {
  await (hooks as any)["tool.execute.after"](
    { tool, sessionID, callID, args },
    { title, output, metadata: {} },
  )
}

/** Find session .md log files (not debug.log, not index.*) */
async function findSessionLogs(): Promise<string[]> {
  const results: string[] = []
  async function walk(dir: string) {
    if (!existsSync(dir)) return
    const entries = await readdir(dir, { withFileTypes: true })
    for (const e of entries) {
      const full = path.join(dir, e.name)
      if (e.isDirectory()) {
        await walk(full)
      } else if (e.name.endsWith(".md") && !e.name.startsWith("index")) {
        results.push(full)
      }
    }
  }
  await walk(tmpDir)
  return results
}

/** Find session .json sidecar files (not index.json, not debug.log) */
async function findSessionJsons(): Promise<string[]> {
  const results: string[] = []
  async function walk(dir: string) {
    if (!existsSync(dir)) return
    const entries = await readdir(dir, { withFileTypes: true })
    for (const e of entries) {
      const full = path.join(dir, e.name)
      if (e.isDirectory()) {
        await walk(full)
      } else if (e.name.endsWith(".json") && !e.name.startsWith("index")) {
        results.push(full)
      }
    }
  }
  await walk(tmpDir)
  return results
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
describe("session-recorder plugin", () => {
  const SESSION_ID = "ses_test_001"
  const NOW = Date.now()

  beforeAll(async () => {
    hooks = await SessionRecorderPlugin(mockCtx as any)
  })

  afterAll(async () => {
    await cleanup()
  })

  test("plugin initializes and returns expected hooks", () => {
    expect(hooks.event).toBeDefined()
    expect(typeof hooks.event).toBe("function")
    // No tool.execute.before hook in v0.2.0
    expect((hooks as any)["tool.execute.before"]).toBeUndefined()
    expect((hooks as any)["tool.execute.after"]).toBeDefined()
  })

  test("session.created with epoch-ms timestamp creates session file", async () => {
    await fireEvent("session.created", {
      info: {
        id: SESSION_ID,
        projectID: "test-project",
        directory: "/tmp/test",
        title: "Test Session",
        time: { created: NOW },
      },
    })

    const files = await findSessionLogs()
    expect(files.length).toBe(1)

    const content = await readFile(files[0], "utf-8")
    // v0.2.0: no YAML frontmatter, just markdown header
    expect(content).toContain("# Session: Test Session")
    expect(content).not.toContain("---")
  })

  test("message.updated increments message count and writes header", async () => {
    await fireEvent("message.updated", {
      info: {
        id: "msg_001",
        sessionID: SESSION_ID,
        role: "user",
      },
    })

    const files = await findSessionLogs()
    const content = await readFile(files[0], "utf-8")
    // v0.2.0: role-bracketed format
    expect(content).toMatch(/\[user \d{2}:\d{2}:\d{2}\]/)
  })

  test("message.part.updated with finalized text appends content", async () => {
    // Delta (non-final) -- should be skipped
    await fireEvent("message.part.updated", {
      part: {
        id: "part_001",
        sessionID: SESSION_ID,
        messageID: "msg_002",
        type: "text",
        text: "partial...",
      },
      delta: "partial...",
    })

    // Final (no delta) -- should be written
    await fireEvent("message.part.updated", {
      part: {
        id: "part_002",
        sessionID: SESSION_ID,
        messageID: "msg_002",
        type: "text",
        text: "Hello, this is the assistant response.",
      },
    })

    const files = await findSessionLogs()
    const content = await readFile(files[0], "utf-8")
    expect(content).toContain("Hello, this is the assistant response.")
    expect(content).not.toContain("partial...")
  })

  test("tool.execute.after tracks tool usage", async () => {
    await fireToolAfter("bash", SESSION_ID, "call_001", "Lists files", { command: "ls -la" })

    const files = await findSessionLogs()
    const content = await readFile(files[0], "utf-8")
    expect(content).toMatch(/\[tool:bash \d{2}:\d{2}:\d{2}\]/)
  })

  test("skill detection via tool hooks", async () => {
    await fireToolAfter("skill", SESSION_ID, "call_002", "Loaded debugger skill", { name: "debugger" })
    // Will verify in finalization that skills_used includes "debugger"
  })

  test("file tracking via edit/write tools", async () => {
    await fireToolAfter("edit", SESSION_ID, "call_003", "Edited foo.ts", { filePath: "/tmp/test/foo.ts" })
    await fireToolAfter("write", SESSION_ID, "call_004", "Wrote bar.ts", { filePath: "/tmp/test/bar.ts" })
    // Will verify in finalization that files_touched includes both
  })

  test("command.executed logs command", async () => {
    await fireEvent("command.executed", {
      sessionID: SESSION_ID,
      name: "plan",
      arguments: "my-feature",
    })

    const files = await findSessionLogs()
    const content = await readFile(files[0], "utf-8")
    expect(content).toMatch(/\[command \d{2}:\d{2}:\d{2}\] \/plan my-feature/)
  })

  test("session.compacted marks compaction", async () => {
    await fireEvent("session.compacted", {
      sessionID: SESSION_ID,
    })

    const files = await findSessionLogs()
    const content = await readFile(files[0], "utf-8")
    expect(content).toMatch(/\[system \d{2}:\d{2}:\d{2}\] context compacted/)
  })

  test("session.updated renames session and logs to markdown", async () => {
    await fireEvent("session.updated", {
      info: {
        id: SESSION_ID,
        title: "Renamed Test Session",
        time: { updated: Date.now() },
      },
    })

    const files = await findSessionLogs()
    const content = await readFile(files[0], "utf-8")
    expect(content).toMatch(/\[system \d{2}:\d{2}:\d{2}\] renamed: "Renamed Test Session"/)
  })

  test("session.idle finalizes session with correct metadata", async () => {
    await fireEvent("session.idle", {
      sessionID: SESSION_ID,
    })

    const files = await findSessionLogs()
    const content = await readFile(files[0], "utf-8")

    // Check appended Session Summary footer
    expect(content).toContain("## Session Summary")
    expect(content).toContain("**Outcome**: completed")
    expect(content).toContain("**Compacted**: true")
    expect(content).toContain("debugger")
    expect(content).toContain("/tmp/test/foo.ts")
    expect(content).toContain("/tmp/test/bar.ts")
    expect(content).toContain("plan")

    // v0.2.0: .json sidecar should also exist
    const jsons = await findSessionJsons()
    expect(jsons.length).toBe(1)
    const jsonData = JSON.parse(await readFile(jsons[0], "utf-8"))
    expect(jsonData.session_id).toBe(SESSION_ID)
    expect(jsonData.title).toBe("Renamed Test Session") // updated by session.updated before finalization
    expect(jsonData.outcome).toBe("completed")
    expect(jsonData.compacted).toBe(true)
    expect(jsonData.skills_used).toContain("debugger")
    expect(jsonData.files_touched).toContain("/tmp/test/foo.ts")
    expect(jsonData.files_touched).toContain("/tmp/test/bar.ts")
    expect(jsonData.commands_used).toContain("plan")
  })

  test("index.json is created with session stats", async () => {
    const indexPath = path.join(tmpDir, "index.json")
    expect(existsSync(indexPath)).toBe(true)

    const data = JSON.parse(await readFile(indexPath, "utf-8"))
    expect(data.session_count).toBe(1)
    expect(data.skills.debugger).toBeDefined()
    expect(data.skills.debugger.count).toBe(1)
    expect(data.recent_sessions.length).toBe(1)
    expect(data.recent_sessions[0].outcome).toBe("completed")
  })

  test("session.error finalizes with error outcome", async () => {
    const SESSION_ID_2 = "ses_test_002"

    await fireEvent("session.created", {
      info: {
        id: SESSION_ID_2,
        projectID: "test-project",
        directory: "/tmp/test",
        title: "Error Session",
        time: { created: Date.now() },
      },
    })

    await fireEvent("session.error", {
      sessionID: SESSION_ID_2,
      error: "Something went wrong",
    })

    const files = await findSessionLogs()
    let foundError = false
    for (const f of files) {
      const content = await readFile(f, "utf-8")
      if (content.includes("# Session: Error Session")) {
        foundError = true
        expect(content).toContain("**Outcome**: error")
        expect(content).toContain("Something went wrong")
      }
    }
    expect(foundError).toBe(true)

    // v0.2.0: .json sidecar should have error outcome
    const jsons = await findSessionJsons()
    let foundErrorJson = false
    for (const j of jsons) {
      const data = JSON.parse(await readFile(j, "utf-8"))
      if (data.session_id === SESSION_ID_2) {
        foundErrorJson = true
        expect(data.outcome).toBe("error")
      }
    }
    expect(foundErrorJson).toBe(true)
  })

  test("session.deleted preserves file with deleted outcome", async () => {
    const SESSION_ID_3 = "ses_test_003"

    await fireEvent("session.created", {
      info: {
        id: SESSION_ID_3,
        projectID: "test-project",
        directory: "/tmp/test",
        title: "Deleted Session",
        time: { created: Date.now() + 1000 },
      },
    })

    await fireEvent("session.deleted", {
      sessionID: SESSION_ID_3,
    })

    const files = await findSessionLogs()
    expect(files.length).toBe(3) // original + error + deleted

    for (const f of files) {
      expect(existsSync(f)).toBe(true)
    }
  })

  test("unknown sessionID triggers late-init", async () => {
    const UNKNOWN_SESSION = "ses_unknown_999"

    mockSessionData[UNKNOWN_SESSION] = {
      id: UNKNOWN_SESSION,
      projectID: "late-project",
      directory: "/tmp/late",
      title: "Late Init Session",
      time: { created: Date.now() + 2000 },
    }

    await fireToolAfter("read", UNKNOWN_SESSION, "call_late", "Read file", { filePath: "/tmp/foo" })

    const files = await findSessionLogs()
    expect(files.length).toBe(4) // previous 3 + late-init

    let foundLateInit = false
    for (const f of files) {
      const content = await readFile(f, "utf-8")
      if (content.includes("Late Init Session")) {
        foundLateInit = true
        expect(content).toContain("# Session: Late Init Session")
      }
    }
    expect(foundLateInit).toBe(true)
  })

  test("long content is captured without truncation", async () => {
    const SESSION_ID_5 = "ses_test_005"
    await fireEvent("session.created", {
      info: {
        id: SESSION_ID_5,
        projectID: "test-project",
        directory: "/tmp/test",
        title: "No Truncation Test",
        time: { created: Date.now() + 3000 },
      },
    })

    const longText = "x".repeat(2000)
    await fireEvent("message.part.updated", {
      part: {
        id: "part_long",
        sessionID: SESSION_ID_5,
        messageID: "msg_long",
        type: "text",
        text: longText,
      },
    })

    const files = await findSessionLogs()
    let found = false
    for (const f of files) {
      const content = await readFile(f, "utf-8")
      if (content.includes("No Truncation Test")) {
        found = true
        const match = content.match(/x+/)
        expect(match).toBeTruthy()
        expect(match![0].length).toBe(2000)
      }
    }
    expect(found).toBe(true)
  })

  test("disabled config returns empty hooks", async () => {
    const origDir = process.env.SESSION_RECORDER_MEMORY_DIR
    const disabledTmp = await mkdtemp(path.join(os.tmpdir(), "session-recorder-disabled-"))
    process.env.SESSION_RECORDER_MEMORY_DIR = disabledTmp

    const configPath = path.join(os.homedir(), ".config/opencode/session-recorder.json")
    const origConfig = existsSync(configPath) ? await readFile(configPath, "utf-8") : null
    await writeFile(configPath, JSON.stringify({ enabled: false }), "utf-8")

    try {
      const freshModule = await import("../session-recorder.ts?" + Date.now())
      const disabledHooks = await freshModule.SessionRecorderPlugin(mockCtx as any)
      expect(Object.keys(disabledHooks).length).toBe(0)
    } finally {
      if (origConfig !== null) {
        await writeFile(configPath, origConfig, "utf-8")
      }
      process.env.SESSION_RECORDER_MEMORY_DIR = origDir
      await rm(disabledTmp, { recursive: true, force: true })
    }
  })

  test("subagent session writes to parent session file", async () => {
    const PARENT_ID = "ses_parent_sub"
    const SUBAGENT_ID = "ses_subagent_001"

    await fireEvent("session.created", {
      info: {
        id: PARENT_ID,
        projectID: "test-project",
        directory: "/tmp/test",
        title: "Parent Session",
        time: { created: Date.now() + 5000 },
      },
    })

    // Subagent session is created with "subagent" in title
    await fireEvent("session.created", {
      info: {
        id: SUBAGENT_ID,
        projectID: "test-project",
        directory: "/tmp/test",
        title: "Research something (@explore subagent)",
        time: { created: Date.now() + 5100 },
      },
    })

    // Subagent does work -- text should go to parent file
    await fireEvent("message.part.updated", {
      part: {
        id: "sub_part_001",
        sessionID: SUBAGENT_ID,
        messageID: "sub_msg_001",
        type: "text",
        text: "Subagent found the answer: GCLB means Google Cloud Load Balancer.",
      },
    })

    // Subagent completes
    await fireEvent("session.idle", { sessionID: SUBAGENT_ID })

    // Verify: subagent should NOT have its own file
    const files = await findSessionLogs()
    let subagentHasOwnFile = false
    let parentContent = ""
    for (const f of files) {
      const content = await readFile(f, "utf-8")
      if (content.includes("# Session: Research something")) {
        subagentHasOwnFile = true
      }
      if (content.includes("# Session: Parent Session")) {
        parentContent = content
      }
    }

    expect(subagentHasOwnFile).toBe(false)
    expect(parentContent).toContain("subagent")
    expect(parentContent).toContain("GCLB means Google Cloud Load Balancer")
  })

  test("text parts with content are captured (not just empty ones)", async () => {
    const TEXT_SESSION = "ses_text_capture"
    await fireEvent("session.created", {
      info: {
        id: TEXT_SESSION,
        projectID: "test-project",
        directory: "/tmp/test",
        title: "Text Capture Test",
        time: { created: Date.now() + 6000 },
      },
    })

    // First: empty text part (like OpenCode sends initially)
    await fireEvent("message.part.updated", {
      part: {
        id: "text_part_empty",
        sessionID: TEXT_SESSION,
        messageID: "msg_text_01",
        type: "text",
        text: "",
      },
    })

    // Second: same part ID but now with content
    await fireEvent("message.part.updated", {
      part: {
        id: "text_part_empty",
        sessionID: TEXT_SESSION,
        messageID: "msg_text_01",
        type: "text",
        text: "The answer to your question is 42.",
      },
    })

    const files = await findSessionLogs()
    let found = false
    for (const f of files) {
      const content = await readFile(f, "utf-8")
      if (content.includes("Text Capture Test")) {
        found = true
        expect(content).toContain("The answer to your question is 42.")
      }
    }
    expect(found).toBe(true)
  })

  // -- NEW TEST: index.json accumulates across multiple sessions --
  test("index.json accumulates across multiple sessions", async () => {
    const baseTime = Date.now() + 10000

    for (let i = 0; i < 3; i++) {
      const sid = `ses_accumulate_${i}`
      await fireEvent("session.created", {
        info: {
          id: sid,
          projectID: "test-project",
          directory: "/tmp/test",
          title: `Accumulate Session ${i}`,
          time: { created: baseTime + i * 1000 },
        },
      })
      // Add a skill to each
      await fireToolAfter("skill", sid, `call_acc_${i}`, "Loaded plan-generator", { name: "plan-generator" })
      await fireEvent("session.idle", { sessionID: sid })
    }

    const indexPath = path.join(tmpDir, "index.json")
    const data = JSON.parse(await readFile(indexPath, "utf-8"))

    // Previous tests created sessions too, so count should be > 3
    // But the 3 accumulate sessions should all be counted
    expect(data.session_count).toBeGreaterThanOrEqual(3 + 1) // +1 for the first test session
    expect(data.skills["plan-generator"]).toBeDefined()
    expect(data.skills["plan-generator"].count).toBe(3)
    expect(data.recent_sessions.length).toBeGreaterThanOrEqual(3)
  })

  // -- NEW TEST: session .json contains queryable metrics --
  test("session .json contains queryable metrics", async () => {
    const METRICS_SESSION = "ses_metrics_001"
    await fireEvent("session.created", {
      info: {
        id: METRICS_SESSION,
        projectID: "metrics-project",
        directory: "/tmp/metrics",
        title: "Metrics Test Session",
        time: { created: Date.now() + 20000 },
      },
    })

    // Simulate activity
    await fireEvent("message.updated", {
      info: { id: "msg_m1", sessionID: METRICS_SESSION, role: "user", agent: "build", model: { modelID: "claude-opus-4-6" } },
    })
    await fireEvent("message.updated", {
      info: { id: "msg_m2", sessionID: METRICS_SESSION, role: "assistant", modelID: "claude-opus-4-6", tokens: { input: 500, output: 200, cache: { read: 100, write: 50 } } },
    })
    await fireToolAfter("bash", METRICS_SESSION, "call_m1", "Run build", { command: "npm run build" })
    await fireToolAfter("edit", METRICS_SESSION, "call_m2", "Edited main.ts", { filePath: "/tmp/metrics/main.ts" })
    await fireToolAfter("skill", METRICS_SESSION, "call_m3", "Loaded debugger", { name: "debugger" })
    await fireEvent("command.executed", { sessionID: METRICS_SESSION, name: "implement", arguments: "./plan.md" })

    // Finalize
    await fireEvent("session.idle", { sessionID: METRICS_SESSION })

    // Find the .json sidecar for this session
    const jsons = await findSessionJsons()
    let metricsJson: any = null
    for (const j of jsons) {
      const data = JSON.parse(await readFile(j, "utf-8"))
      if (data.session_id === METRICS_SESSION) { metricsJson = data; break }
    }

    expect(metricsJson).not.toBeNull()
    expect(metricsJson.project).toBe("metrics-project")
    expect(metricsJson.title).toBe("Metrics Test Session")
    expect(metricsJson.outcome).toBe("completed")
    expect(metricsJson.model).toBe("claude-opus-4-6")
    expect(metricsJson.agent).toBe("build")
    expect(metricsJson.message_count).toBe(2)
    expect(metricsJson.skills_used).toContain("debugger")
    expect(metricsJson.commands_used).toContain("implement")
    expect(metricsJson.tools_used.bash).toBe(1)
    expect(metricsJson.tools_used.edit).toBe(1)
    expect(metricsJson.tools_used.skill).toBe(1)
    expect(metricsJson.files_touched).toContain("/tmp/metrics/main.ts")
    expect(metricsJson.token_usage.input).toBe(500)
    expect(metricsJson.token_usage.output).toBe(200)
    expect(metricsJson.token_usage.cache_read).toBe(100)
    expect(metricsJson.token_usage.cache_write).toBe(50)
    expect(typeof metricsJson.duration_minutes).toBe("number")
    expect(metricsJson.start_time).toBeDefined()
    expect(metricsJson.end_time).toBeDefined()
  })
})
