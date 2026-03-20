/**
 * Consensus Tools Plugin for OpenCode
 *
 * Provides:
 * - `list_critics`: Discovers available critic agents at runtime.
 * - `spawn_critics`: Spawns ALL available critics in parallel via
 *   SubtaskPartInput. Used by the consensus agent to guarantee true
 *   parallel execution at the code level.
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
  // -- Helpers --

  /**
   * Resolve where critic sessions should be parented.
   *
   * When consensus is itself a subagent (e.g., plan-generator -> consensus),
   * critics parented to the consensus session become grandchildren of the
   * top-level session and TUI navigation can't reach them. Fix: parent
   * critics to the consensus session's parent instead (one level up).
   *
   * When consensus IS the top-level session (no parent), critics stay
   * parented to it directly.
   */
  async function resolveParentForCritics(sessionId: string): Promise<string> {
    try {
      const res = await ctx.client.session.get({ path: { id: sessionId } })
      const parentID = (res.data as any)?.parentID
      if (parentID) return parentID
    } catch { /* fall through to current session */ }
    return sessionId
  }

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

  return {
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

      spawn_critics: tool({
        description:
          "Spawn ALL available critics in parallel to evaluate items. " +
          "Creates one child session per critic, fires SubtaskPartInput " +
          "via promptAsync, polls for completion, and returns structured results.",
        args: {
          prompt: tool.schema.string().describe("The complete evaluation prompt to send to each critic"),
          label: tool.schema.string().optional().describe("Optional label for progress display"),
        },
        async execute(args, context) {
          const critics = await discoverCritics()

          if (critics.length === 0) {
            return JSON.stringify({
              critics: [],
              results: [],
              summary: "No critic agents configured.",
            })
          }

          const startTime = Date.now()

          context.metadata({ title: `spawning ${critics.length} critics in parallel...` })

          // Resolve the correct parent for critic sessions.
          const criticParentID = await resolveParentForCritics(context.sessionID)

          // Create wrapper sessions and fire SubtaskPartInput in parallel
          const results = await Promise.all(
            critics.map(async (criticName) => {
              const st = Date.now()
              try {
                const sessionRes = await ctx.client.session.create({
                  body: {
                    parentID: criticParentID,
                    title: `${criticName} evaluation subagent`,
                  },
                })
                if (!sessionRes.data?.id) {
                  return { critic: criticName, status: "error" as const, response: "Failed to create session" }
                }
                const sessionId = sessionRes.data.id

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
          })

          return JSON.stringify({
            critics,
            results,
            summary: `${critics.length} critics in parallel (${duration}). ${succeeded} succeeded.`,
          })
        },
      }),
    },
  }
}
