# Shared Agents Base

Canonical base directory for agent-agnostic agentic workflows. Consumed by Pi (and any future coding agent harness).

## Directory Structure

```
~/.agents/
  AGENTS.md    -- Agent protocol (shared by all harnesses)
  skills/      -- Skill definitions (agentskills.io standard)
  commands/    -- Slash-command prompts (pi prompt template format)
```

## What Lives Here

- `AGENTS.md` -- Agent-agnostic protocol defining how agents should behave (action protocol, failure handling, checkpoints, code standards, etc.)
- `skills/` -- Skill methodology files. Each harness discovers these natively or via an extension.
- `commands/` -- Slash-command prompts such as `/commit` and `/plan`: one Markdown file per command with `description` frontmatter and `$ARGUMENTS` placeholders.
- `...` -- any other shared context

## What Does NOT Live Here

- Extensions/tools -- these are harness-specific implementations (`~/.pi/agent/extensions/`)
- Provider configuration -- handled by each harness's settings

## Harness Integration

- Pi: discovers skills from `~/.agents/skills/` natively. AGENTS.md loaded via the `agents-context` extension. `~/.pi/agent/prompts` is a symlink to `commands/`, so pi loads the commands as prompt templates.

