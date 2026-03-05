/**
 * Power Guard Plugin for OpenCode (v1.0.0)
 *
 * Prevents macOS system idle sleep while OpenCode sessions are actively working.
 * Uses `caffeinate -i` to hold a power assertion only when agents are busy.
 *
 * Behavior:
 *   - When any session transitions to "busy", spawns `caffeinate -i`
 *   - When ALL sessions become idle/complete/error, kills caffeinate
 *   - Cleans up caffeinate process on OpenCode exit
 *
 * This does NOT prevent lid-close sleep (macOS firmware-level, cannot be overridden).
 * It DOES prevent the system from idle-sleeping while your agents are working.
 *
 * macOS only -- no-ops gracefully on other platforms.
 */
import type { Plugin } from "@opencode-ai/plugin"
import { spawn, type ChildProcess } from "child_process"
import { platform } from "os"

const PLUGIN_NAME = "power-guard"
const IS_MACOS = platform() === "darwin"

export const PowerGuardPlugin: Plugin = async (ctx) => {
  if (!IS_MACOS) {
    try {
      await ctx.client.app.log({
        body: {
          service: PLUGIN_NAME,
          level: "info",
          message: "Not macOS -- power-guard disabled",
        },
      })
    } catch {}
    return {}
  }

  const busySessions = new Set<string>()
  let caffeinateProc: ChildProcess | null = null

  const log = async (level: "debug" | "info" | "warn" | "error", message: string) => {
    try {
      await ctx.client.app.log({
        body: { service: PLUGIN_NAME, level, message },
      })
    } catch {}
  }

  function startCaffeinate(): void {
    if (caffeinateProc) return

    try {
      // -i = prevent idle sleep
      // -w <pid> = release when this process (opencode) exits
      caffeinateProc = spawn("caffeinate", ["-i", "-w", String(process.pid)], {
        stdio: "ignore",
        detached: false,
      })

      caffeinateProc.on("error", (err) => {
        log("error", `caffeinate spawn error: ${err.message}`)
        caffeinateProc = null
      })

      caffeinateProc.on("exit", (code) => {
        // Only log if we didn't kill it ourselves
        if (caffeinateProc !== null) {
          log("debug", `caffeinate exited unexpectedly (code=${code})`)
        }
        caffeinateProc = null
      })

      log("info", `caffeinate started (pid=${caffeinateProc.pid}) -- idle sleep prevented`)
    } catch (err) {
      log("error", `failed to start caffeinate: ${err}`)
      caffeinateProc = null
    }
  }

  function stopCaffeinate(): void {
    if (!caffeinateProc) return

    const pid = caffeinateProc.pid
    try {
      caffeinateProc.kill("SIGTERM")
    } catch {}
    const ref = caffeinateProc
    caffeinateProc = null
    log("info", `caffeinate stopped (pid=${pid}) -- idle sleep allowed`)
  }

  function onSessionBusy(sessionID: string): void {
    const wasFree = busySessions.size === 0
    busySessions.add(sessionID)
    if (wasFree) {
      startCaffeinate()
    }
  }

  function onSessionFree(sessionID: string): void {
    busySessions.delete(sessionID)
    if (busySessions.size === 0) {
      stopCaffeinate()
    }
  }

  // Clean up on process exit
  const cleanup = () => {
    if (caffeinateProc) {
      try { caffeinateProc.kill("SIGTERM") } catch {}
      caffeinateProc = null
    }
  }
  process.on("exit", cleanup)
  process.on("SIGINT", cleanup)
  process.on("SIGTERM", cleanup)

  await log("info", "power-guard plugin initialized")

  return {
    event: async ({ event }: { event: any }) => {
      switch (event.type) {
        case "session.status": {
          const { sessionID, status } = event.properties
          if (status.type === "busy") {
            onSessionBusy(sessionID)
          } else {
            // "idle" or "retry" -- session is not actively consuming resources
            onSessionFree(sessionID)
          }
          break
        }

        case "session.idle":
        case "session.error":
        case "session.deleted": {
          onSessionFree(event.properties.sessionID)
          break
        }
      }
    },
  }
}
