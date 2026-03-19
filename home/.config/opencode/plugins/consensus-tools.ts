/**
 * Consensus Tools Plugin for OpenCode
 *
 * Provides:
 * - `list_critics`: Discovers available critic agents at runtime.
 * - `task` (override): Replaces the built-in task tool. For normal calls,
 *   replicates built-in behavior via the SDK. For the consensus agent calling
 *   critic agents, batches and runs ALL critics in parallel.
 *
 * The custom task tool produces proper TUI-visible, clickable ToolParts
 * because the TUI renders `tool === "task"` with the task component.
 *
 * The tool.execute.after hook injects metadata.sessionId into the completed
 * ToolPart so the TUI renders a clickable link to the child session.
 */
import type { Plugin } from "@opencode-ai/plugin"
import { tool } from "@opencode-ai/plugin"
import { getPluginConfig } from "../lib/plugin-config.ts"

interface ConsensusToolsConfig {
  timeout_ms: number
  poll_interval_ms: number
}

const CONFIG_DEFAULTS: ConsensusToolsConfig = {
  timeout_ms: 5 * 60 * 1000,
  poll_interval_ms: 2000,
}

const config = getPluginConfig("consensus-tools", CONFIG_DEFAULTS)

export const ConsensusToolsPlugin: Plugin = async (ctx) => {
  // -- Shared state for the tool.execute.after hook --
  // Maps callID -> sessionId so the hook can inject metadata.sessionId
  // into the completed ToolPart.
  const sessionByCall: Record<string, string> = {}

  // -- Helpers --

  async function discoverCritics(): Promise<string[]> {
    const res = await ctx.client.app.agents()
    const agents = res.data ?? []
    return agents
      .filter((a: any) => a.name?.startsWith("critic/"))
      .map((a: any) => a.name as string)
  }

  function extractVote(text: string): string {
    if (/\bKEEP\b/i.test(text)) return "KEEP"
    if (/\bREJECT\b/i.test(text)) return "REJECT"
    return "ABSTAIN"
  }

  function formatDuration(ms: number): string {
    if (ms < 1000) return `${ms}ms`
    const secs = Math.floor(ms / 1000)
    if (secs < 60) return `${secs}s`
    return `${Math.floor(secs / 60)}m ${secs % 60}s`
  }

  async function waitForIdle(sessionId: string, timeoutMs: number): Promise<boolean> {
    const deadline = Date.now() + timeoutMs
    while (Date.now() < deadline) {
      try {
        const res = await ctx.client.session.status()
        const s = (res.data ?? {})[sessionId]
        if (!s || s.type === "idle") return true
      } catch { /* keep polling */ }
      await new Promise((r) => setTimeout(r, config.poll_interval_ms))
    }
    return false
  }

  async function extractResponse(sessionId: string): Promise<string> {
    for (let attempt = 0; attempt < 5; attempt++) {
      const res = await ctx.client.session.messages({ path: { id: sessionId } })
      const msgs = res.data ?? []
      for (let i = msgs.length - 1; i >= 0; i--) {
        for (const part of msgs[i].parts ?? []) {
          if ((part as any).type === "tool" && (part as any).tool === "task") {
            const output = (part as any).state?.output
            if ((part as any).state?.status === "completed" && output) return output
          }
        }
      }
      for (let i = msgs.length - 1; i >= 0; i--) {
        if (msgs[i].info.role === "assistant") {
          const text = (msgs[i].parts ?? [])
            .filter((p: any) => p.type === "text" && p.text)
            .map((p: any) => p.text)
            .join("\n").trim()
          if (text) return text
        }
      }
      if (attempt < 4) await new Promise((r) => setTimeout(r, 1000))
    }
    return ""
  }

  // -- Normal task execution (replicates built-in behavior via SDK) --

  async function executeNormalTask(
    args: { description: string; prompt: string; subagent_type: string; task_id?: string },
    context: any,
  ): Promise<string> {
    // Create or resume child session
    let sessionId: string
    if (args.task_id) {
      sessionId = args.task_id
    } else {
      const sessionRes = await ctx.client.session.create({
        body: {
          parentID: context.sessionID,
          title: `${args.description} (@${args.subagent_type} subagent)`,
        },
      })
      if (!sessionRes.data?.id) throw new Error("Failed to create session")
      sessionId = sessionRes.data.id
    }

    // Set metadata so TUI shows clickable link while running
    context.metadata({
      title: args.description,
      metadata: { sessionId },
    })

    // Store for the tool.execute.after hook
    sessionByCall[context.sessionID] = sessionId

    // Run the prompt synchronously (like built-in TaskTool)
    const promptRes = await ctx.client.session.prompt({
      path: { id: sessionId },
      body: {
        agent: args.subagent_type,
        parts: [{ type: "text" as const, text: args.prompt }],
      },
    })

    // Extract text from response
    const parts = (promptRes as any).data?.parts ?? []
    const output = parts
      .filter((p: any) => p.type === "text" && p.text)
      .map((p: any) => p.text)
      .join("\n").trim() || "Task completed."

    return output
  }

  // -- Parallel critic execution --

  async function executeParallelCritics(
    args: { description: string; prompt: string },
    context: any,
    critics: string[],
  ): Promise<string> {
    const startTime = Date.now()

    context.metadata({ title: `spawning ${critics.length} critics in parallel...` })

    // Create wrapper sessions and fire SubtaskPartInput in parallel
    const results = await Promise.all(
      critics.map(async (criticName) => {
        const st = Date.now()
        try {
          const sessionRes = await ctx.client.session.create({
            body: {
              parentID: context.sessionID,
              title: `${criticName} evaluation subagent`,
            },
          })
          if (!sessionRes.data?.id) {
            return { critic: criticName, status: "error" as const, response: "Failed to create session" }
          }
          const sessionId = sessionRes.data.id

          // Store first session for the hook
          if (!sessionByCall[context.sessionID]) {
            sessionByCall[context.sessionID] = sessionId
            context.metadata({
              title: `spawning ${critics.length} critics in parallel...`,
              metadata: { sessionId },
            })
          }

          await ctx.client.session.promptAsync({
            path: { id: sessionId },
            body: {
              parts: [{
                type: "subtask" as const,
                prompt: args.prompt,
                description: `${criticName} evaluation`,
                agent: criticName,
              }],
            },
          })

          if (!await waitForIdle(sessionId, config.timeout_ms)) {
            try { await ctx.client.session.abort({ path: { id: sessionId } }) } catch {}
            return { critic: criticName, status: "timeout" as const, response: "Timed out", sessionId, durationMs: Date.now() - st }
          }

          const response = await extractResponse(sessionId)
          if (!response) {
            return { critic: criticName, status: "error" as const, response: "Empty response", sessionId, durationMs: Date.now() - st }
          }

          return { critic: criticName, status: "success" as const, response, sessionId, durationMs: Date.now() - st }
        } catch (err) {
          return { critic: criticName, status: "error" as const, response: String(err) }
        }
      }),
    )

    const succeeded = results.filter((r) => r.status === "success").length
    const duration = formatDuration(Date.now() - startTime)
    const votes = results.map((r) => {
      const vote = r.status === "success" ? extractVote(r.response) : "ABSTAIN"
      return `${r.critic.replace("critic/", "")}=${vote}`
    }).join(", ")

    context.metadata({
      title: `${critics.length} critics complete (${votes})`,
      metadata: { sessionId: sessionByCall[context.sessionID] },
    })

    return JSON.stringify({
      critics,
      results,
      summary: `${critics.length} critics in parallel (${duration}). ${succeeded} succeeded.`,
    })
  }

  return {
    "tool.execute.after": async (input, output) => {
      if (input.tool !== "task") return
      const sessionId = sessionByCall[input.sessionID]
      try {
        await ctx.client.app.log({ body: {
          service: "consensus-tools",
          message: `tool.execute.after: tool=${input.tool} sessionID=${input.sessionID} storedSessionId=${sessionId ?? "none"} currentMeta=${JSON.stringify(output.metadata)}`,
        } as any })
      } catch {}
      if (sessionId) {
        output.metadata = { ...output.metadata, sessionId }
        delete sessionByCall[input.sessionID]
      }
    },

    tool: {
      list_critics: tool({
        description:
          "List all available critic agents. Returns a JSON array of critic " +
          'agent names (e.g., ["critic/claude", "critic/gemini"]).',
        args: {},
        async execute() {
          return JSON.stringify(await discoverCritics())
        },
      }),

      task: tool({
        description:
          "Launch a new agent to handle complex, multistep tasks autonomously. " +
          "When the calling agent is consensus and the subagent_type is a critic " +
          "agent, this tool batches ALL available critics and runs them in parallel.",
        args: {
          description: tool.schema.string().describe("A short (3-5 words) description of the task"),
          prompt: tool.schema.string().describe("The task for the agent to perform"),
          subagent_type: tool.schema.string().describe("The type of specialized agent to use for this task"),
          task_id: tool.schema.string().optional().describe(
            "Set to resume a previous task (continues the same subagent session).",
          ),
        },
        async execute(args, context) {
          const critics = await discoverCritics()
          const isCriticCall = critics.includes(args.subagent_type)
          const isConsensusAgent = context.agent === "consensus"

          if (isConsensusAgent && isCriticCall) {
            // Consensus agent calling a critic: batch ALL critics in parallel
            return executeParallelCritics(
              { description: args.description, prompt: args.prompt },
              context,
              critics,
            )
          }

          // Normal task execution -- replicate built-in behavior
          return executeNormalTask(args, context)
        },
      }),
    },
  }
}
