/**
 * Session Recorder Plugin for OpenCode (v0.2.0)
 *
 * Dual-format architecture: .json for metrics, .md for conversation logs.
 * Zero external dependencies beyond @opencode-ai/plugin.
 *
 * Configuration (in ~/.config/opencode/session-recorder.json):
 *   enabled, debug, memory_dir, max_recent_sessions
 */
import type { Plugin } from "@opencode-ai/plugin"
import { mkdir, writeFile, readFile, appendFile, rename } from "fs/promises"
import { existsSync } from "fs"
import path from "path"

// -- Config & Constants --
const PLUGIN_VERSION = "0.2.0"

interface SessionRecorderConfig {
  enabled: boolean
  debug: "off" | "error" | "info" | "debug"
  memory_dir: string
  max_recent_sessions: number
}

const CONFIG_DEFAULTS: SessionRecorderConfig = {
  enabled: true,
  debug: "error",
  memory_dir: path.join(process.env.HOME!, ".config/opencode/memory"),
  max_recent_sessions: 10,
}

function loadConfigSync(): SessionRecorderConfig {
  const configPath = path.join(process.env.HOME!, ".config/opencode/session-recorder.json")
  if (existsSync(configPath)) {
    try {
      const raw = require("fs").readFileSync(configPath, "utf-8")
      return { ...CONFIG_DEFAULTS, ...JSON.parse(raw) }
    } catch { /* Malformed config -- use defaults */ }
  }
  return { ...CONFIG_DEFAULTS }
}

const config = loadConfigSync()
if (process.env.SESSION_RECORDER_MEMORY_DIR) {
  config.memory_dir = process.env.SESSION_RECORDER_MEMORY_DIR
}
const MEMORY_DIR = config.memory_dir
const INDEX_PATH = path.join(MEMORY_DIR, "index.json")
const DEBUG_LOG = path.join(MEMORY_DIR, "debug.log")

// -- Debug Logging --
const DEBUG_LEVELS = { off: 0, error: 1, info: 2, debug: 3 } as const
const INSTANCE_ID = Math.random().toString(36).slice(2, 6)

function shouldLog(level: keyof typeof DEBUG_LEVELS): boolean {
  return DEBUG_LEVELS[config.debug] >= DEBUG_LEVELS[level]
}

async function debugLog(msg: string, level: keyof typeof DEBUG_LEVELS = "debug"): Promise<void> {
  if (!shouldLog(level)) return
  try {
    const line = `[${new Date().toISOString()}] [${INSTANCE_ID}] [${level}] ${msg}\n`
    await mkdir(MEMORY_DIR, { recursive: true })
    await appendFile(DEBUG_LOG, line, "utf-8")
  } catch { /* swallow */ }
}

void debugLog(`session-recorder v${PLUGIN_VERSION} module loaded`, "error")

// -- Types & State --
interface SessionState {
  sessionId: string
  filePath: string
  project: string
  directory: string
  title: string
  startTime: string
  model: string
  agent: string
  skillsUsed: Set<string>
  commandsUsed: Set<string>
  toolsUsed: Map<string, number>
  filesTouched: Set<string>
  messageCount: number
  compacted: boolean
  tokenUsage: { input: number; output: number; cacheRead: number; cacheWrite: number }
  seenMessages: Set<string>
  finalizedParts: Set<string>
}

/** Dependencies injected from plugin init -- avoids closure coupling. */
interface Deps {
  client: any
  log: (msg: string) => Promise<void>
  logError: (msg: string) => Promise<void>
}

const sessions = new Map<string, SessionState>()
const subagentToParent = new Map<string, SessionState>()

// -- Helpers --
function toISO(value: any): string {
  if (typeof value === "number") return new Date(value).toISOString()
  if (typeof value === "string" && /^\d+$/.test(value)) return new Date(Number(value)).toISOString()
  if (typeof value === "string") return value
  return new Date().toISOString()
}

function toSafeFilename(iso: string): string { return iso.replace(/:/g, "-") }

function sessionBasePath(iso: string): string {
  const d = new Date(iso)
  const yyyy = d.getUTCFullYear().toString()
  const mm = String(d.getUTCMonth() + 1).padStart(2, "0")
  return path.join(MEMORY_DIR, yyyy, mm, toSafeFilename(iso))
}

function nowHHMMSS(): string { return new Date().toISOString().slice(11, 19) }

async function appendToLog(filePath: string, content: string): Promise<void> {
  await appendFile(filePath, content, "utf-8")
}

function resolveSession(id: string): SessionState | undefined {
  return subagentToParent.get(id) ?? sessions.get(id)
}

function makeState(id: string, fp: string, project: string, directory: string, title: string, startTime: string): SessionState {
  return {
    sessionId: id, filePath: fp, project, directory, title, startTime,
    model: "", agent: "",
    skillsUsed: new Set(), commandsUsed: new Set(), toolsUsed: new Map(),
    filesTouched: new Set(), messageCount: 0, compacted: false,
    tokenUsage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
    seenMessages: new Set(), finalizedParts: new Set(),
  }
}

/** Resolve session, falling back to lateInit for sessions created before plugin load. */
async function resolveOrInit(sessionId: string, deps: Deps): Promise<SessionState | undefined> {
  return resolveSession(sessionId) ?? await lateInit(sessionId, deps)
}

// -- File Operations --
async function createSessionLog(state: SessionState): Promise<void> {
  if (existsSync(state.filePath)) return
  await mkdir(path.dirname(state.filePath), { recursive: true })
  await writeFile(state.filePath, `# Session: ${state.title}\n\n`, "utf-8")
}

async function writeSessionJson(state: SessionState, outcome: string, endTime: string, durationMinutes: number): Promise<void> {
  const jsonPath = state.filePath.replace(/\.md$/, ".json")
  const data = {
    session_id: state.sessionId, project: state.project, directory: state.directory,
    title: state.title, date: state.startTime.slice(0, 10),
    start_time: state.startTime, end_time: endTime,
    duration_minutes: durationMinutes, outcome,
    model: state.model || "unknown", agent: state.agent || "unknown",
    message_count: state.messageCount, compacted: state.compacted,
    skills_used: [...state.skillsUsed].sort(), commands_used: [...state.commandsUsed].sort(),
    tools_used: Object.fromEntries(state.toolsUsed),
    files_touched: [...state.filesTouched].sort(),
    token_usage: { input: state.tokenUsage.input, output: state.tokenUsage.output,
      cache_read: state.tokenUsage.cacheRead, cache_write: state.tokenUsage.cacheWrite },
  }
  await writeFile(jsonPath, JSON.stringify(data, null, 2) + "\n", "utf-8")
}

async function appendSummaryFooter(state: SessionState, outcome: string, endTime: string, durationMinutes: number): Promise<void> {
  const footer = [
    `\n## Session Summary\n`,
    `- **Outcome**: ${outcome}`,
    `- **Duration**: ${durationMinutes} minutes`,
    `- **Messages**: ${state.messageCount}`,
    `- **Model**: ${state.model || "unknown"}`,
    `- **Agent**: ${state.agent || "unknown"}`,
    `- **Skills**: ${[...state.skillsUsed].sort().join(", ") || "none"}`,
    `- **Commands**: ${[...state.commandsUsed].sort().join(", ") || "none"}`,
    `- **Tools**: ${[...state.toolsUsed.entries()].map(([k, v]) => `${k}(${v})`).join(", ") || "none"}`,
    `- **Files touched**: ${[...state.filesTouched].sort().join(", ") || "none"}`,
    `- **Tokens**: input=${state.tokenUsage.input} output=${state.tokenUsage.output} cache_read=${state.tokenUsage.cacheRead}`,
    `- **Compacted**: ${state.compacted}`,
    `- **End time**: ${endTime}`,
    "",
  ].join("\n")
  await appendToLog(state.filePath, footer)
}

// -- Index Operations --
interface IndexData {
  last_updated: string
  session_count: number
  skills: Record<string, { count: number; last_used: string }>
  commands: Record<string, { count: number; last_used: string }>
  models: Record<string, { sessions: number; input_tokens: number; output_tokens: number }>
  recent_sessions: Array<{ date: string; duration: string; outcome: string; skills: string; project: string }>
}

function readIndex(): IndexData {
  const defaults: IndexData = { last_updated: "", session_count: 0, skills: {}, commands: {}, models: {}, recent_sessions: [] }
  try {
    if (!existsSync(INDEX_PATH)) return defaults
    const raw = require("fs").readFileSync(INDEX_PATH, "utf-8")
    return { ...defaults, ...JSON.parse(raw) }
  } catch { return defaults }
}

function writeIndexFile(data: IndexData): void {
  const tmpPath = INDEX_PATH + `.${process.pid}.tmp`
  require("fs").writeFileSync(tmpPath, JSON.stringify(data, null, 2) + "\n", "utf-8")
  require("fs").renameSync(tmpPath, INDEX_PATH)
}

function updateIndex(state: SessionState, outcome: string, durationMinutes: number): void {
  try {
    const data = readIndex()
    const today = new Date().toISOString().slice(0, 10)
    data.last_updated = today
    data.session_count += 1

    for (const skill of state.skillsUsed) {
      if (!data.skills[skill]) data.skills[skill] = { count: 0, last_used: "" }
      data.skills[skill].count += 1
      data.skills[skill].last_used = today
    }
    for (const cmd of state.commandsUsed) {
      if (!data.commands[cmd]) data.commands[cmd] = { count: 0, last_used: "" }
      data.commands[cmd].count += 1
      data.commands[cmd].last_used = today
    }
    if (state.model) {
      if (!data.models[state.model]) data.models[state.model] = { sessions: 0, input_tokens: 0, output_tokens: 0 }
      data.models[state.model].sessions += 1
      data.models[state.model].input_tokens += state.tokenUsage.input
      data.models[state.model].output_tokens += state.tokenUsage.output
    }
    data.recent_sessions.unshift({
      date: state.startTime.slice(0, 16).replace("T", " "),
      duration: `${durationMinutes}m`,
      outcome,
      skills: [...state.skillsUsed].sort().join(", ") || "none",
      project: state.project,
    })
    data.recent_sessions = data.recent_sessions.slice(0, config.max_recent_sessions)
    writeIndexFile(data)
    void debugLog(`updateIndex: success, session_count=${data.session_count}`, "error")
  } catch (err) {
    void debugLog(`updateIndex: FAILED: ${err}`, "error")
  }
}

// -- Subagent & Late Init --
function isSubagent(title: string): boolean { return title.includes("subagent") }

function findParent(sessionId: string, project: string): SessionState | undefined {
  let candidate: SessionState | undefined
  for (const [, s] of sessions) {
    if (s.sessionId !== sessionId && s.project === project) candidate = s
  }
  return candidate
}

async function lateInit(sessionId: string, deps: Deps): Promise<SessionState | undefined> {
  try {
    const res = await deps.client.session.get({ path: { id: sessionId } })
    const info = res.data
    if (!info) return undefined

    const startTime = toISO(info.time?.created)
    const fp = sessionBasePath(startTime) + ".md"
    const state = makeState(sessionId, fp, info.projectID ?? "unknown", info.directory ?? "", info.title ?? sessionId, startTime)

    if (isSubagent(state.title)) {
      const parent = findParent(sessionId, state.project)
      if (parent) { subagentToParent.set(sessionId, parent); return parent }
    }

    sessions.set(sessionId, state)
    await createSessionLog(state)
    return state
  } catch (err) {
    await deps.logError(`session-recorder: late-init failed for ${sessionId}: ${err}`)
    return undefined
  }
}

// -- Finalization --
async function finalizeSession(state: SessionState, outcome: string, deps: Deps): Promise<void> {
  try {
    if (!existsSync(state.filePath)) return
    const endTime = new Date().toISOString()
    const durationMinutes = Math.round((new Date(endTime).getTime() - new Date(state.startTime).getTime()) / 60000)
    await appendSummaryFooter(state, outcome, endTime, durationMinutes)
    await writeSessionJson(state, outcome, endTime, durationMinutes)
    updateIndex(state, outcome, durationMinutes)
    sessions.delete(state.sessionId)
  } catch (err) {
    await debugLog(`finalizeSession: ERROR: ${err}`, "error")
    await deps.logError(`session-recorder: finalize error: ${err}`)
  }
}

// =========================================================================
// Event Handlers -- one function per event type
// =========================================================================

async function onSessionCreated(props: any, deps: Deps): Promise<void> {
  const info = props?.info
  if (!info?.id) return

  const startTime = toISO(info.time?.created)
  const fp = sessionBasePath(startTime) + ".md"
  const state = makeState(info.id, fp, info.projectID ?? "unknown", info.directory ?? "", info.title ?? info.id, startTime)

  if (isSubagent(state.title)) {
    const parent = findParent(info.id, state.project)
    if (parent) {
      subagentToParent.set(info.id, parent)
      await appendToLog(parent.filePath, `\n[subagent:${state.agent || "unknown"} ${nowHHMMSS()}]\n> task: ${state.title}\n\n`)
      return
    }
  }

  sessions.set(info.id, state)
  await createSessionLog(state)
  await deps.log(`session-recorder: tracking session ${info.id}`)
}

async function onMessageUpdated(props: any, deps: Deps): Promise<void> {
  const info = props?.info
  if (!info?.sessionID) return

  const state = await resolveOrInit(info.sessionID, deps)
  if (!state) return

  const msgId = info.id ?? `${info.sessionID}-${state.messageCount}`
  if (state.seenMessages.has(msgId)) return
  state.seenMessages.add(msgId)
  state.messageCount += 1

  if (info.role === "user") {
    if (info.agent && !state.agent) state.agent = info.agent
    if (info.model?.modelID && !state.model) state.model = info.model.modelID
  } else if (info.role === "assistant") {
    if (info.modelID && !state.model) state.model = info.modelID
    if (info.tokens) {
      state.tokenUsage.input += info.tokens.input ?? 0
      state.tokenUsage.output += info.tokens.output ?? 0
      state.tokenUsage.cacheRead += info.tokens.cache?.read ?? 0
      state.tokenUsage.cacheWrite += info.tokens.cache?.write ?? 0
    }
  }

  await appendToLog(state.filePath, `\n[${info.role} ${nowHHMMSS()}]\n`)
}

async function onMessagePartUpdated(props: any, deps: Deps): Promise<void> {
  const part = props?.part
  if (!part?.sessionID) return

  const state = await resolveOrInit(part.sessionID, deps)
  if (!state) return
  if (props?.delta !== undefined) return

  if (part.type === "text") {
    if (!part.text) return
    const partId = part.id ?? `${part.sessionID}-${part.messageID}-text`
    if (state.finalizedParts.has(partId)) return
    state.finalizedParts.add(partId)
    await appendToLog(state.filePath, part.text + "\n\n")
  }
}

async function onCommandExecuted(props: any, deps: Deps): Promise<void> {
  if (!props?.sessionID) return

  const state = await resolveOrInit(props.sessionID, deps)
  if (!state) return

  state.commandsUsed.add(props.name)
  const args = props.arguments ? ` ${props.arguments}` : ""
  await appendToLog(state.filePath, `\n[command ${nowHHMMSS()}] /${props.name}${args}\n`)
}

async function onSessionIdle(props: any, deps: Deps): Promise<void> {
  const sessionId = props?.sessionID
  if (!sessionId) return

  if (subagentToParent.has(sessionId)) {
    subagentToParent.delete(sessionId)
    return
  }

  const state = sessions.get(sessionId)
  if (!state) return
  await finalizeSession(state, "completed", deps)
}

async function onSessionError(props: any, deps: Deps): Promise<void> {
  const sessionId = props?.sessionID
  if (!sessionId) return

  if (subagentToParent.has(sessionId)) {
    const parent = subagentToParent.get(sessionId)!
    const errMsg = props?.error ? String(props.error) : "unknown error"
    await appendToLog(parent.filePath, `\n[system ${nowHHMMSS()}] subagent error: ${errMsg}\n`)
    subagentToParent.delete(sessionId)
    return
  }

  const state = sessions.get(sessionId)
  if (!state) return
  const errMsg = props?.error ? String(props.error) : "unknown error"
  await appendToLog(state.filePath, `\n[system ${nowHHMMSS()}] error: ${errMsg}\n`)
  await finalizeSession(state, "error", deps)
}

async function onSessionCompacted(props: any, deps: Deps): Promise<void> {
  const sessionId = props?.sessionID
  if (!sessionId) return

  const state = resolveSession(sessionId)
  if (!state) return

  state.compacted = true
  await appendToLog(state.filePath, `\n[system ${nowHHMMSS()}] context compacted\n`)
}

async function onSessionDeleted(props: any, deps: Deps): Promise<void> {
  const sessionId = props?.sessionID
  if (!sessionId) return

  if (subagentToParent.has(sessionId)) {
    subagentToParent.delete(sessionId)
    return
  }

  const state = sessions.get(sessionId)
  if (state) {
    await appendToLog(state.filePath, `\n[system ${nowHHMMSS()}] session deleted by user\n`)
    await finalizeSession(state, "deleted", deps)
  }
}

async function onToolExecuteAfter(
  input: { tool: string; sessionID: string; callID: string; args: any },
  output: { title: string; output: string; metadata: any },
  deps: Deps,
): Promise<void> {
  const state = await resolveOrInit(input.sessionID, deps)
  if (!state) return

  // Track usage metrics
  state.toolsUsed.set(input.tool, (state.toolsUsed.get(input.tool) ?? 0) + 1)
  if (input.tool === "skill" && input.args?.name) state.skillsUsed.add(input.args.name)
  if ((input.tool === "edit" || input.tool === "write") && input.args?.filePath) state.filesTouched.add(input.args.filePath)

  await appendToLog(state.filePath, `\n[tool:${input.tool} ${nowHHMMSS()}] ${output.title || input.tool}\n`)
}

// =========================================================================
// Event dispatcher -- maps event.type to handler
// =========================================================================
const EVENT_HANDLERS: Record<string, (props: any, deps: Deps) => Promise<void>> = {
  "session.created": onSessionCreated,
  "message.updated": onMessageUpdated,
  "message.part.updated": onMessagePartUpdated,
  "command.executed": onCommandExecuted,
  "session.idle": onSessionIdle,
  "session.error": onSessionError,
  "session.compacted": onSessionCompacted,
  "session.deleted": onSessionDeleted,
}

// =========================================================================
// Plugin Export -- thin wiring layer
// =========================================================================
export const SessionRecorderPlugin: Plugin = async (ctx) => {
  if (!config.enabled) return {}

  try {
    await mkdir(MEMORY_DIR, { recursive: true })
    await writeFile(DEBUG_LOG, "", "utf-8")
  } catch {}

  await debugLog(`session-recorder v${PLUGIN_VERSION} init, config: ${JSON.stringify(config)}`, "error")

  const deps: Deps = {
    client: ctx.client,
    log: async (msg) => {
      try { await ctx.client.app.log({ body: { service: "session-recorder", level: "info", message: msg } }) } catch {}
    },
    logError: async (msg) => {
      try { await ctx.client.app.log({ body: { service: "session-recorder", level: "error", message: msg } }) } catch {}
    },
  }

  await deps.log("session-recorder plugin initialized")

  return {
    event: async ({ event }: { event: any }) => {
      try {
        if (event.type !== "message.part.delta") await debugLog(`event received: ${event.type}`, "debug")
        const handler = EVENT_HANDLERS[event.type]
        if (handler) await handler(event.properties, deps)
      } catch (err) {
        await deps.logError(`session-recorder: event handler error: ${err}`)
      }
    },

    "tool.execute.after": async (input: any, output: any) => {
      try {
        await onToolExecuteAfter(input, output, deps)
      } catch (err) {
        await deps.logError(`session-recorder: tool.execute.after error: ${err}`)
      }
    },
  }
}
