# Skill Improvement Methodology

Behavior-first, human-gated improvement of instruction files. The former process and dated measurements are retained as historical context, not evidence of current model behavior; see [Protocol evaluation](protocol-evaluation.md) for current scope, contracts, ownership, and approval gates.

## Overview

A skill can pair its instructions with an optional observation log, used only within the authorized notes scope:

- `SKILL.md` -- agent instructions; no universal line-count failure threshold is established. Evaluate induced work, quality, and model/task compatibility; see [Protocol evaluation](protocol-evaluation.md).
- `SKILL_NOTES.md` -- structured observations; capture is append-only, and cleanup or instruction promotion requires human approval.

The inventory below belongs to the historical Feb 25 -- Mar 3, 2026 account, not today's installed/active skill inventory. The current guide records all 18 audited skills and their first-slice dispositions.

| Skill | Purpose | Lines | Observations |
|---|---|---|---|
| plan-generator | Produce implementation plans | 136 | 5 |
| implementer | Execute plans with verification | 150 | 2 |
| pr-description-generator | Generate PR descriptions | 137 | 12 |
| pr-reviewer | Review PRs with categorized findings | 116 | 4 |
| codebase-explorer | Map unfamiliar codebases | 64 | 0 |
| debugger | Scientific debugging | 74 | 0 |
| skill-improver | Meta-skill: improve other skills | 60 | 0 |

## Feedback Loop

### Fast Loop (conditional)

Capture is conditional on novel reusable evidence and the notes opt-out; do not spawn an observer after every execution. Historical examples and metrics below describe the former process, not current requirements.

Only when capture is relevant and authorized, the caller resolves `SKIP_SKILL_NOTES` from the environment, NEVER `.env`; `1` or `true` disables notes. Reuse an applicable resolved flag and evidence. A delegated observer requires the parent's explicit `notes_enabled=true`, target, concrete observation, and evidence in its task text; missing/false enablement means no notes I/O, environment-tool search, or replacement workflow.

One owner may append at most one batched entry per skill/session after checking relevant evidence for novelty and duplication. Ordinary success or a paraphrase of instructions is not an observation; no recursive observer or automatic `SKILL.md` change follows.

Historical entry example (unchanged):

```markdown
### 2026-03-02 | Successful Pattern | pr-description-generator
**Context:** Generated PR desc for a config-only change.
**Observation:** Testing section was thin -- no source or test files to reference.
**Takeaway:** Omit Testing section when diff contains no source/test files.
**Actionability:** ready-to-promote
```

The historical subagent description specified edits only to `*SKILL_NOTES.md`, temperature 0.1, a 10-step budget, and no bash/web access. Those settings and the former “sandboxed” description are not current runtime guarantees. The current `skill-improver` agent declares `read`, `edit`, and `write`; its invocation contract limits it to enabled, evidence-backed notes capture, not instruction changes, shell commands, `.env` reads, trackers, or another observer. A declared role/tool list is not proof of filesystem sandboxing.

Observations use `ready-to-promote` | `needs-more-data` | `question-for-user`, but a tag is not approval or proof. Categories are `Edge Case` | `Successful Pattern` | `Open Question` | `Deviation` | `Tool Limitation`.

### Slow Loop (human-gated)

An explicit `/improve-skill` request dispatches to `improve-skills`, not the `skill-improver` observer. Review the named target, or all skills only when batch/all was requested. Reuse applicable evidence, propose a targeted diff with expected behavioral effect and uncertainty, and obtain human approval before changing `SKILL.md` or cleaning up notes. Preserve the requested review product without manufacturing follow-on work. Promotion hierarchy:

1. **Generalize** (preferred) -- collapse edge cases into one principle
2. **Replace** -- new principle supersedes old
3. **Compress** -- same meaning, fewer words
4. **Append** (last resort) -- genuinely new, no overlap

The historical signal-to-noise question was “If I removed this line, would the agent behave differently?” Also ask whether that difference helps the task, safety, or necessary coordination. Repeated notes or shorter text alone do not establish cross-task/model benefit; validate proposed changes against applicable behavior cases.

### Governance

The `skill-health` diagnostic is a scoped, read-only audit of triggers, owners, induced work, intended benefits, evidence, and retain/gate/repair/retire recommendations. Broken references, conflicting obligations, unsupported work, and missing safety/stop conditions matter more than line counts. Size and age are secondary diagnostics, not ceilings or automatic cleanup triggers; do not read private logs merely to populate a metrics table or introduce subagents just to shorten prose.

The shared protocol owns authorization and stopping; skills own domain work; wrappers bind inputs once; leaf agents return assigned evidence. Actual runtime injection and source-owner blockers can still conflict with these contracts. Local scorer/text tests establish neither LLM compliance nor integrated deployment; behavioral promotion needs the separate approvals and profile-specific gates in the current guide.

## Metrics (7 days: Feb 25 -- Mar 3, 2026)

Historical measurements and examples below are preserved as originally recorded. They are selected authoring/usage observations, not a controlled evaluation of quality, reduced unnecessary work, cross-model reliability, or current deployed behavior.

### Activity

| Metric | Value |
|---|---|
| Commits touching skill files | 13 (of 222 total) |
| Observations captured | 23 |
| Promoted to SKILL.md | 4 (17%) |
| Ready for promotion | 10 (43%) |
| Accumulating data | 7 (30%) |
| Open questions | 1 (4%) |
| Total SKILL.md lines (all skills) | 737 |
| Total SKILL.md words (all skills) | 5,313 |

### Compression

The historical account described smaller files with added guidance; these size changes alone do not establish improved capability or task outcomes:

| Skill | Initial | Current | Delta |
|---|---|---|---|
| implementer | 230 | 150 | **-35%** |
| plan-generator | 155 | 136 | **-12%** |
| pr-description-generator | 141 | 137 | **-3%** |

The implementer lost 80 lines by replacing verbose procedures with principles (14-line task extraction -> 4 lines, 10-line retry pseudocode -> 1 sentence, 12 rules -> 6) while adding tool integrations and behavioral rules.

### Observation Distribution

```
pr-description-generator  ████████████  12 (52%)
plan-generator            █████          5 (22%)
pr-reviewer               ████           4 (17%)
implementer               ██             2 (9%)
```

Feedback density correlates with execution frequency. Three skills with zero observations are used less often.

### Promotion Example

The "omit Testing for docs PRs" rule:

1. Feb 27: *"Testing section thin for docs-only PR."* -> `ready-to-promote`
2. Mar 2: *"Config-only PR also had sparse Testing."* -> `ready-to-promote`
3. Mar 3: Third data point. All three promoted into one SKILL.md line.

3 observations -> 1 instruction. 4 days from first observation to promotion.

### Timeline

```
Feb 25  Skills created (implementer: 230 lines, plan-gen: 155, pr-desc: 141)
Feb 26  First compression wave; explorer + debugger added; tool integrations
Feb 27  Feedback loop built (skill-improver subagent, skill-health command)
Mar 02  SKILL_NOTES format standardized; actionability triage added
Mar 03  pr-reviewer created (pre-standardized); first 4 promotions
```

## Architecture

Current ownership sketch, not an automatic pipeline or an enforced sandbox:

```text
Explicit request -> thin wrapper -> selected skill -> requested result
                                           |
                    novel reusable evidence + authorized + notes enabled?
                         no: stop              yes: one capture owner
                                                      |
                                     SKILL_NOTES.md (append-only capture)
                                     at most one entry per skill/session
                                                      |
                                      user-requested /improve-skill review
                                                      |
                                     evidence + proposed diff + uncertainty
                                                      |
                                             human approval
                                                      |
                                         scoped SKILL.md change
```

The capture gate belongs to one caller, not both wrapper and skill. An observer is optional, receives the resolved enablement explicitly, and does not coordinate a second workflow. Instruction changes require evidence and human approval, not a line-count target or a quota of observations.
