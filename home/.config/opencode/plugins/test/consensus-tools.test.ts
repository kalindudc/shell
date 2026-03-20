/**
 * Test harness for consensus-tools plugin.
 *
 * Run: bun test plugins/test/consensus-tools.test.ts
 */
import { describe, test, expect, beforeAll, afterAll } from "bun:test"
import { rm, mkdtemp } from "fs/promises"
import path from "path"
import os from "os"

const { ConsensusToolsPlugin } = await import("../consensus-tools.ts")

let tmpDir: string
tmpDir = await mkdtemp(path.join(os.tmpdir(), "consensus-tools-test-"))

// ---------------------------------------------------------------------------
// Mock SDK
// ---------------------------------------------------------------------------
interface ApiCall { method: string; args: any; timestamp: number }
const apiCalls: ApiCall[] = []

const sessionStore: Record<string, {
  id: string; parentID?: string; title: string;
  status: "idle" | "busy"; messages: Array<{ info: any; parts: any[] }>
}> = {}

const mockAgents = [
  { name: "build", mode: "primary" },
  { name: "critic/claude", mode: "subagent" },
  { name: "critic/gemini", mode: "subagent" },
  { name: "critic/gpt", mode: "subagent" },
  { name: "critic/grok", mode: "subagent" },
]

const mockCriticResponses: Record<string, string> = {
  "critic/claude": "**Vote: KEEP**\nReal issue found.",
  "critic/gemini": "**Vote: REJECT**\nSubjective preference.",
  "critic/gpt": "**Vote: KEEP**\nEvidence verified.",
  "critic/grok": "**Vote: REJECT**\nContradicted by source.",
}

let sessionCounter = 0
const metadataCalls: Array<{ title?: string; metadata?: Record<string, any> }> = []

function resetMocks() {
  apiCalls.length = 0
  for (const key of Object.keys(sessionStore)) delete sessionStore[key]
  sessionCounter = 0
  metadataCalls.length = 0
  // Pre-seed the consensus session so session.get can resolve its parentID.
  // Default: consensus is a subagent of "ses_toplevel".
  sessionStore["ses_consensus"] = {
    id: "ses_consensus", parentID: "ses_toplevel", title: "consensus subagent",
    status: "idle", messages: [],
  }
}

const mockClient = {
  app: {
    agents: async () => {
      apiCalls.push({ method: "app.agents", args: {}, timestamp: Date.now() })
      return { data: mockAgents }
    },
  },
  session: {
    create: async ({ body }: any) => {
      apiCalls.push({ method: "session.create", args: body, timestamp: Date.now() })
      const id = `ses_mock_${++sessionCounter}`
      sessionStore[id] = { id, parentID: body?.parentID, title: body?.title ?? "", status: "idle", messages: [] }
      return { data: { id, parentID: body?.parentID, title: body?.title } }
    },
    promptAsync: async ({ path: p, body }: any) => {
      apiCalls.push({ method: "session.promptAsync", args: { path: p, body }, timestamp: Date.now() })
      const session = sessionStore[p.id]
      if (session) {
        session.status = "busy"
        const subtask = body.parts?.find((p: any) => p.type === "subtask")
        const agent = subtask?.agent ?? "unknown"
        const response = mockCriticResponses[agent] ?? "No mock"
        setTimeout(() => {
          session.messages.push(
            { info: { role: "user", id: `u_${session.id}` }, parts: body.parts },
            { info: { role: "assistant", id: `a_${session.id}` }, parts: [{
              type: "tool", tool: "task",
              state: { status: "completed", output: response, metadata: { sessionId: `ses_critic_${agent}` } },
            }] },
          )
          session.status = "idle"
        }, 50)
      }
      return { data: undefined }
    },
    status: async () => {
      apiCalls.push({ method: "session.status", args: {}, timestamp: Date.now() })
      const statuses: Record<string, any> = {}
      for (const [id, s] of Object.entries(sessionStore)) statuses[id] = { type: s.status }
      return { data: statuses }
    },
    messages: async ({ path: p }: any) => {
      apiCalls.push({ method: "session.messages", args: { path: p }, timestamp: Date.now() })
      return { data: sessionStore[p.id]?.messages ?? [] }
    },
    get: async ({ path: p }: any) => {
      apiCalls.push({ method: "session.get", args: { path: p }, timestamp: Date.now() })
      const s = sessionStore[p.id]
      return { data: s ? { id: s.id, parentID: s.parentID, title: s.title } : undefined }
    },
    abort: async ({ path: p }: any) => {
      const s = sessionStore[p.id]; if (s) s.status = "idle"
      return { data: true }
    },
  },
}

const mockCtx = {
  client: mockClient, project: "test", directory: tmpDir, worktree: tmpDir,
  serverUrl: new URL("http://localhost:4096"), $: (() => {}) as any,
}

type Hooks = Awaited<ReturnType<typeof ConsensusToolsPlugin>>
let hooks: Hooks
const toolCtx = {
  sessionID: "ses_consensus", messageID: "msg_1", agent: "consensus",
  directory: tmpDir, worktree: tmpDir, abort: new AbortController().signal,
  metadata: (input: any) => { metadataCalls.push(input) }, ask: async () => {},
}

beforeAll(async () => { hooks = await ConsensusToolsPlugin(mockCtx as any) })
afterAll(async () => { if (tmpDir.includes("consensus-tools-test-")) await rm(tmpDir, { recursive: true, force: true }) })

// ---------------------------------------------------------------------------
// list_critics
// ---------------------------------------------------------------------------
describe("list_critics", () => {
  test("discovers critic agents", async () => {
    resetMocks()
    expect(JSON.parse(await hooks.tool!.list_critics.execute({}, toolCtx as any)))
      .toEqual(["critic/claude", "critic/gemini", "critic/gpt", "critic/grok"])
  })

  test("returns empty when no critics", async () => {
    const orig = mockAgents.slice()
    mockAgents.length = 0; mockAgents.push({ name: "build", mode: "primary" })
    resetMocks()
    expect(JSON.parse(await hooks.tool!.list_critics.execute({}, toolCtx as any))).toEqual([])
    mockAgents.length = 0; mockAgents.push(...orig)
  })
})

// ---------------------------------------------------------------------------
// spawn_critics -- sessions
// ---------------------------------------------------------------------------
describe("spawn_critics sessions", () => {
  test("creates one child session per critic", async () => {
    resetMocks()
    await hooks.tool!.spawn_critics.execute({ prompt: "Evaluate" }, toolCtx as any)
    expect(apiCalls.filter((c) => c.method === "session.create").length).toBe(4)
  })

  test("all children parented to consensus session's parent (top-level)", async () => {
    resetMocks()
    await hooks.tool!.spawn_critics.execute({ prompt: "Evaluate" }, toolCtx as any)
    // ses_consensus has parentID "ses_toplevel", so critics should be
    // parented there -- not to the consensus session itself.
    for (const call of apiCalls.filter((c) => c.method === "session.create")) {
      expect(call.args.parentID).toBe("ses_toplevel")
    }
  })

  test("children parented to consensus when consensus is top-level", async () => {
    resetMocks()
    // Override: consensus has no parent (it IS the top-level session)
    sessionStore["ses_consensus"] = {
      id: "ses_consensus", parentID: undefined, title: "consensus",
      status: "idle", messages: [],
    }
    await hooks.tool!.spawn_critics.execute({ prompt: "Evaluate" }, toolCtx as any)
    for (const call of apiCalls.filter((c) => c.method === "session.create")) {
      expect(call.args.parentID).toBe("ses_consensus")
    }
  })

  test("titles include critic name and subagent", async () => {
    resetMocks()
    await hooks.tool!.spawn_critics.execute({ prompt: "Evaluate" }, toolCtx as any)
    for (const call of apiCalls.filter((c) => c.method === "session.create")) {
      expect(call.args.title).toContain("subagent")
      expect(call.args.title).toMatch(/critic\//)
    }
  })
})

// ---------------------------------------------------------------------------
// spawn_critics -- SubtaskPartInput
// ---------------------------------------------------------------------------
describe("spawn_critics SubtaskPartInput", () => {
  test("sends SubtaskPartInput to each wrapper via promptAsync", async () => {
    resetMocks()
    await hooks.tool!.spawn_critics.execute({ prompt: "Test prompt" }, toolCtx as any)
    const calls = apiCalls.filter((c) => c.method === "session.promptAsync")
    expect(calls.length).toBe(4)
    for (const call of calls) {
      const parts = call.args.body.parts
      expect(parts.length).toBe(1)
      expect(parts[0].type).toBe("subtask")
      expect(parts[0].prompt).toBe("Test prompt")
      expect(parts[0].agent).toMatch(/^critic\//)
    }
  })

  test("targets all 4 critic agents", async () => {
    resetMocks()
    await hooks.tool!.spawn_critics.execute({ prompt: "x" }, toolCtx as any)
    const agents = apiCalls.filter((c) => c.method === "session.promptAsync")
      .map((c) => c.args.body.parts[0].agent).sort()
    expect(agents).toEqual(["critic/claude", "critic/gemini", "critic/gpt", "critic/grok"])
  })

  test("all prompts fired before polling", async () => {
    resetMocks()
    await hooks.tool!.spawn_critics.execute({ prompt: "x" }, toolCtx as any)
    const prompts = apiCalls.filter((c) => c.method === "session.promptAsync").map((c) => c.timestamp)
    const firstPoll = apiCalls.filter((c) => c.method === "session.status").map((c) => c.timestamp)[0]
    if (firstPoll) for (const ts of prompts) expect(ts).toBeLessThanOrEqual(firstPoll + 10)
  })
})

// ---------------------------------------------------------------------------
// spawn_critics -- responses
// ---------------------------------------------------------------------------
describe("spawn_critics responses", () => {
  test("extracts responses from task ToolPart output", async () => {
    resetMocks()
    const parsed = JSON.parse(await hooks.tool!.spawn_critics.execute({ prompt: "x" }, toolCtx as any))
    expect(parsed.results.length).toBe(4)
    for (const r of parsed.results) {
      expect(r.status).toBe("success")
      expect(r.response).toBe(mockCriticResponses[r.critic])
    }
  })

  test("summary includes counts", async () => {
    resetMocks()
    const parsed = JSON.parse(await hooks.tool!.spawn_critics.execute({ prompt: "x" }, toolCtx as any))
    expect(parsed.summary).toContain("4 succeeded")
  })

  test("returns empty when no critics", async () => {
    const orig = mockAgents.slice()
    mockAgents.length = 0; mockAgents.push({ name: "build", mode: "primary" })
    resetMocks()
    const parsed = JSON.parse(await hooks.tool!.spawn_critics.execute({ prompt: "x" }, toolCtx as any))
    expect(parsed.critics.length).toBe(0)
    expect(parsed.summary).toContain("No critic agents configured")
    mockAgents.length = 0; mockAgents.push(...orig)
  })
})

// ---------------------------------------------------------------------------
// spawn_critics -- metadata
// ---------------------------------------------------------------------------
describe("spawn_critics metadata", () => {
  test("sets initial title showing spawning", async () => {
    resetMocks()
    await hooks.tool!.spawn_critics.execute({ prompt: "x" }, toolCtx as any)
    expect(metadataCalls[0].title).toContain("spawning")
    expect(metadataCalls[0].title).toContain("4")
  })

  test("sets final title with vote summary", async () => {
    resetMocks()
    await hooks.tool!.spawn_critics.execute({ prompt: "x" }, toolCtx as any)
    const last = metadataCalls[metadataCalls.length - 1]
    expect(last.title).toContain("complete")
    expect(last.title).toContain("KEEP")
    expect(last.title).toContain("REJECT")
  })
})

// ---------------------------------------------------------------------------
// spawn_critics -- errors
// ---------------------------------------------------------------------------
describe("spawn_critics errors", () => {
  test("handles session creation failure", async () => {
    const orig = mockClient.session.create
    let n = 0
    mockClient.session.create = async ({ body }: any) => { n++; return n === 2 ? { data: null } : orig({ body }) }
    resetMocks()
    const parsed = JSON.parse(await hooks.tool!.spawn_critics.execute({ prompt: "x" }, toolCtx as any))
    expect(parsed.results.filter((r: any) => r.status === "error").length).toBe(1)
    expect(parsed.results.filter((r: any) => r.status === "success").length).toBe(3)
    mockClient.session.create = orig
  })
})
