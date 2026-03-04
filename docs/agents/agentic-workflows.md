# Building Skills and Agentic Workflows

Standards for building OpenCode skills, agents, commands, and custom tools.

## Core Philosophy

### Guardrails, not rails

Skills prescribe **behaviors and principles**, not rigid scripts. The agent decides how to apply the methodology.

- **Guardrail**: "Always reproduce the problem before investigating."
- **Rail**: "Phase 1: Parse the error. Phase 2: Check git log. Phase 3: ..."

Anthropic's SWE-bench agent used a short task prompt with 5 high-level steps, paired with carefully engineered tool definitions. The actual engineering effort went into tool interface design, not elaborate orchestration. Their thesis: keep scaffolding simple, invest in tool interfaces, let the model drive. Mini-SWE-agent demonstrates the same principle -- its ~100-line agent class scores >74% on SWE-bench Verified.

### Signal over noise

Every line in a skill should change agent behavior. If removing a line wouldn't change anything, it's noise.

### Start from use, not from design

Do the task manually first. Notice what worked. Extract the reusable pattern. Iterate from real observations.

---

## Skill Design

### Structure

```markdown
---
name: <kebab-case, matches directory name>
description: <one-line description>
---

# <Skill Name> Skill

## Purpose
<What this skill does and why. 2-5 sentences.>

## Approach
<Principles and behaviors, not rigid phases. List tools and when to use them.>

## Output
<What the agent produces. Format expectations.>

## Self-Improvement
<Append to SKILL_NOTES.md; check SKILL_NOTES.md before executing.>

## Rules
<Hard constraints. Stop conditions. Things the agent must never do.>
```

`## Purpose` is always first. `## Rules` is always last.

### Size

Aim for under 150 lines. But don't count lines -- ask "is every line earning its space?"

### What belongs in a skill

| Belongs | Doesn't belong |
|---------|----------------|
| Behaviors and principles | Rigid phase transitions with entry/exit criteria |
| Tool references with *when* guidance | Word budgets, exact iteration counts |
| Stop conditions and guardrails | Long examples that consume context |

### Repo-specific skills

Local `.opencode/skills/` should be **better than global** for that repo. Carry repo-specific commands, URLs, patterns, and conventions. If a local skill is just a copy of the global one, delete it.

---

## Agent Design

### Structure

```yaml
---
description: <one-line description>
mode: subagent | primary
temperature: 0.1
steps: 25-40
permission:
  edit:
    "*": deny
    "./tmp/**": allow
  bash: allow
  webfetch: allow
color: info | warning
---

<2-4 sentences: who, what, which skill, key constraints>
```

### Principles

- **Agents** = tool isolation boundaries. Different permissions or modes of operation.
- **Skills** = methodology injection. Repeatable approach, no tool isolation needed.
- **Commands** = user-facing entry points. Wire agents to skills with pre-loaded context.
- **Don't over-restrict tools.** Agents perform better with full access and behavioral guardrails than with tools disabled. The one restriction that consistently helps: preventing source file modification during investigation.

### Subagent vs. Primary

- **Subagent**: invoked via `@mention` or Task tool. Isolated context. Good for exploration.
- **Primary**: cycled via Tab. Shared conversation. Good for debugging inline.

---

## Command Design

### Structure

```markdown
---
description: <one-line description>
agent: <agent-name>
subtask: true
---

Load the `<skill-name>` skill and follow its instructions to <verb>: $ARGUMENTS

!`ls -la`
!`git log --oneline -10`

## Rules
<3-5 command-specific rules>
```

### Principles

- Commands are **thin wrappers**. The skill has the methodology.
- Shell output injection (`!`command``) pre-loads context to save tool calls.
- `agent:` inherits permissions. Don't duplicate permission logic.
- `subtask: true` for isolated sessions (exploration). Skip it for inline work (debugging).

---

## Custom Tool Design

### When to build

Build when the agent consistently chains 3+ bash commands for one answer, output parsing is error-prone, or structural analysis is needed. Don't build for one-off tasks or simple single commands.

### Structure

```typescript
import { tool } from "@opencode-ai/plugin"

export default tool({
  description: "What this does and when to use it (not just what)",
  args: {
    param: tool.schema.string().describe("What this parameter is"),
  },
  async execute(args, context) {
    // Shell out to CLI tools, parse structured output
    // Return structured JSON, not raw text
    // Limit output (20 matches, not 2000)
    // Degrade gracefully if dependencies missing
  },
})
```

### Principles

- **Description matters** -- it's the prompt context the agent sees.
- **Return structured data**, not raw text.
- **Limit output** to protect the context window.
- **Reference tools in skills** -- undiscoverable tools don't get used.

---

## Self-Improvement

### Two-loop model

```
Fast loop (every use): Agent appends observations to SKILL_NOTES.md
Slow loop (periodic):  User runs /improve-skill, reviews and approves changes
```

**SKILL.md** = principles (human-gated). **SKILL_NOTES.md** = observations (agent-writable).

### Distillation over accumulation

When promoting observations to principles:

1. **Generalize**: Multiple edge cases -> one principle. Prefer this.
2. **Replace**: New principle supersedes old. Remove the old.
3. **Compress**: Same meaning, fewer words.
4. **Append**: Genuinely new. Last resort.

### SKILL_NOTES.md conventions

- Timestamp entries (YYYY-MM-DD), one idea per entry
- Old irrelevant notes are candidates for removal
- Notes contradicting principles are important signals

---

## The Workflow Chain

```
/explore -> /debug -> /plan -> /plan-review -> /implement -> /pr-desc
```

Each stage is optional. Use what's needed. See `docs/planning-methodology.md` for the plan -> review -> implement pipeline in detail.

| Stage | Purpose | Agent | Output |
|-------|---------|-------|--------|
| Explore | Understand codebase | `codebase-explorer` | Report in `./tmp/` |
| Debug | Diagnose a bug | `debugger` | Report in `./tmp/` |
| Plan | Design implementation | default | Plan in `./tmp/plan/` |
| Plan Review | Validate plan before implementing | default | Review in `./tmp/plan-review/` |
| Implement | Execute plan | default | Code changes |
| PR Description | Document changes | default | PR desc in `./tmp/pr/` |

Handoffs: explorer report -> planning, debugger report -> implementation, plan -> review, review -> implementation, plan + git diff -> PR description.

---

## Anti-Patterns

**Over-engineering skills**: 200+ line skills with rigid phases, word budgets, iteration counts. Removes model judgment. Fix: strip to principles + behaviors.

**Restricting tools instead of guiding behavior**: Disabling tools to prevent misuse. The agent loses needed capabilities. Fix: guide through skill instructions. Only restrict source file modification during investigation.

**Copying global skills without adaptation**: Identical repo-local copies of global skills. Maintenance burden, zero benefit. Fix: delete the local copy or make it genuinely better with repo-specific context.

**Accumulating patches**: Skills growing as edge cases and workarounds are appended. Core principles get buried. Fix: use the distillation workflow (Generalize > Replace > Compress > Append).

---

## Research References

| Source | Finding | Application |
|--------|---------|-------------|
| Anthropic SWE-bench agent | Short task prompt + carefully engineered tool interfaces outperformed complex orchestration. "More time optimizing tools than the overall prompt." | Minimal scaffolding, invest in tool design |
| Mini-SWE-agent | ~100-line agent class, >74% on SWE-bench Verified | Simple agents with good models go far |
| Self-Debugging (Chen et al., 2023) | Rubber-duck debugging (explain code, then diagnose) improves accuracy 2-3% without test feedback; up to 12% with unit test feedback | "Explain before hypothesizing" in debugger |
| SWE-Search (Antoniades et al., ICLR 2025) | MCTS with LLM value estimation achieves 23% relative improvement (~4-7pp absolute) over linear agents on SWE-bench Lite | Backtracking and self-evaluation over linear attempts |
| Agentless (Xia et al., 2024) | Hierarchical localization (files -> classes -> edit lines) in a simple pipeline, competitive at 2-5x lower cost than expensive agent approaches | "Start broad, narrow deliberately" in explorer |
| Anthropic Claude 4.6 migration guide | Workarounds for older model behavior (anti-laziness, aggressive tool prompting) cause overtriggering on newer models | Review and remove accumulated workarounds on model upgrades |
