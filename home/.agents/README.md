# Shared Agents Base

Canonical base directory for agent-agnostic agentic workflows. Consumed by both Pi and OpenCode (and any future coding agent harness).

## Directory Structure

```
~/.agents/
  AGENTS.md    -- Agent protocol (shared by all harnesses)
  skills/      -- Skill definitions (agentskills.io standard)
```

## What Lives Here

- `AGENTS.md` -- Agent-agnostic protocol defining how agents should behave (action protocol, failure handling, checkpoints, code standards, etc.)
- `skills/` -- Skill methodology files. Each harness discovers these natively or via an extension.
- `...` -- any other shared context

## What Does NOT Live Here

- Commands/prompts -- these are runtime-specific and live in each harness's config directory (`~/.pi/agent/prompts/`, `~/.config/opencode/commands/`)
- Extensions/tools -- these are harness-specific implementations (`~/.pi/agent/extensions/`, `~/.config/opencode/tools/`)
- Provider configuration -- handled by each harness's settings

## Harness Integration

- Pi: discovers skills from `~/.agents/skills/` natively. AGENTS.md loaded via the `agents-context` extension.
- OpenCode: reads AGENTS.md from `~/.config/opencode/AGENTS.md` (separate copy, kept in sync). Skills in `~/.config/opencode/skills/`.

