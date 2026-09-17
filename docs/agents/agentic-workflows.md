# Building Skills and Agentic Workflows

Historical background for agentic workflows. For current behavior-first evaluation, source ownership, and verified Pi contracts, use [Protocol evaluation](protocol-evaluation.md); older harness examples below are not current Pi APIs or blanket permission policy.

The original design examples and research summaries are retained as history, not measured results for the current migration. In particular, YAML permission fields, `@mention`/Tab invocation, shell-output injection, and the file-based workflow table describe older harness conventions. They do not establish runtime isolation or authorize tool access, code execution, persistence, or deployment.

## Core Philosophy

### Guardrails, not rails

Skills prescribe **behaviors and principles**, not rigid scripts. The agent decides how to apply the methodology.

- **Guardrail**: "Always reproduce the problem before investigating."
- **Rail**: "Phase 1: Parse the error. Phase 2: Check git log. Phase 3: ..."

Anthropic's SWE-bench agent used a short task prompt with 5 high-level steps, paired with carefully engineered tool definitions. The actual engineering effort went into tool interface design, not elaborate orchestration. Their thesis: keep scaffolding simple, invest in tool interfaces, let the model drive. Mini-SWE-agent demonstrates the same principle -- its ~100-line agent class scores >74% on SWE-bench Verified.

### Signal over noise

The historical heuristic was that every line should change behavior. A line can also induce useless work: evaluate its task/safety benefit, trigger, owner, and stopping condition, not behavioral effect or brevity alone.

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
<Only capture authorized, novel reusable evidence when notes are enabled; no routine pre-read or observer.>

## Rules
<Hard constraints. Stop conditions. Things the agent must never do.>
```

`## Purpose` first and `## Rules` last are local authoring conventions, not universal loader requirements.

### Size

Earlier guidance aimed for under 150 lines. No universal line-count failure threshold is established: evaluate induced work, correctness, safety, and task/model compatibility. Long on-demand references can be useful; size alone does not warrant deletion, decomposition, or a new orchestrator.

### What belongs in a skill

| Belongs | Doesn't belong |
|---------|----------------|
| Behaviors and principles | Rigid phase transitions with entry/exit criteria |
| Tool references with *when* guidance | Word budgets, exact iteration counts |
| Stop conditions and guardrails | Long examples that consume context |

### Repo-specific skills

Local `.agents/skills/` should be **better than global** for that repo. Carry repo-specific commands, URLs, patterns, and conventions. If a local skill is just a copy of the global one, delete it.

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

- Agents were described as tool-isolation roles; actual permission enforcement depends on the runtime, not this example's metadata.
- Skills supply domain methodology; loading a skill is not an authorization or isolation mechanism.
- Commands are user-facing entry points; current wrappers bind explicit inputs once and dispatch to the selected skill.
- Historical guidance favored broad tool access. This is NOT blanket permission policy: use task-appropriate least privilege and verified runtime boundaries. Behavioral guardrails do not replace sandboxing, and a worktree alone is not a sandbox.

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

## Self-Improvement

### Two-loop model

```
Fast loop (novel evidence, notes enabled): one owner may capture a batched observation; ordinary success starts no follow-on workflow.
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
- Capture is append-only; propose cleanup only with human approval, never automatic deletion based on age
- Notes contradicting principles are important signals

---

## The Workflow Chain

```
/explore -> /debug -> /plan -> /plan-review -> /implement -> /pr-desc
```

This historical chain is illustrative, not a default pipeline. Its command names and file-based outputs are not current Cortex persistence contracts; see the [historical planning methodology](planning-methodology.md) for the former design. Preserve explicitly requested Cortex plans, reviews, reports, and handoffs. Finishing one task does not authorize the next stage.

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

Unsupported work expansion: the former 200+ line heuristic is not a health verdict. Diagnose unsupported obligations, broken references, conflicting ownership, and missing safety/stop conditions; retain useful detailed procedures and examples.

Permission confusion: neither broad tool access nor prose-only guardrails establish safety. Restrict capabilities according to the authorized task and actual runtime isolation; inspect execution side effects rather than assuming all non-editing tools are harmless.

**Copying global skills without adaptation**: Identical repo-local copies of global skills. Maintenance burden, zero benefit. Fix: delete the local copy or make it genuinely better with repo-specific context.

**Accumulating patches**: Skills growing as edge cases and workarounds are appended. Core principles get buried. Fix: use the distillation workflow (Generalize > Replace > Compress > Append).

---

## Historical Research References

These original summaries and numbers are retained unchanged as background. They are not evidence of current shell/Pi behavior, quality noninferiority, reduced unnecessary work, or a deployed rollout; the current guide includes primary sources and counterevidence.

| Source | Finding | Application |
|--------|---------|-------------|
| Anthropic SWE-bench agent | Short task prompt + carefully engineered tool interfaces outperformed complex orchestration. "More time optimizing tools than the overall prompt." | Minimal scaffolding, invest in tool design |
| Mini-SWE-agent | ~100-line agent class, >74% on SWE-bench Verified | Simple agents with good models go far |
| Self-Debugging (Chen et al., 2023) | Rubber-duck debugging (explain code, then diagnose) improves accuracy 2-3% without test feedback; up to 12% with unit test feedback | "Explain before hypothesizing" in debugger |
| SWE-Search (Antoniades et al., ICLR 2025) | MCTS with LLM value estimation achieves 23% relative improvement (~4-7pp absolute) over linear agents on SWE-bench Lite | Backtracking and self-evaluation over linear attempts |
| Agentless (Xia et al., 2024) | Hierarchical localization (files -> classes -> edit lines) in a simple pipeline, competitive at 2-5x lower cost than expensive agent approaches | "Start broad, narrow deliberately" in explorer |
| Anthropic Claude 4.6 migration guide | Workarounds for older model behavior (anti-laziness, aggressive tool prompting) cause overtriggering on newer models | Review and remove accumulated workarounds on model upgrades |
