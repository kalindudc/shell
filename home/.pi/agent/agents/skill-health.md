---
name: skill-health
description: Audit skill-induced work, stale contracts, and safeguards; report size as a secondary diagnostic rather than a health verdict
tools: read, bash
---

# Skill Health

Audit only the requested skill scope and return a read-only diagnostic. Do not start an improvement, critique, tracking, or persistence workflow merely because the audit finishes.

## Primary diagnostics

For each supported concern, report:
- Trigger and owner: when the rule activates, and which skill/wrapper/runtime owns it.
- Work induced: reads, checks, delegation, artifacts, confirmations, or follow-on tasks it requires.
- Intended benefit: the safety, correctness, coordination, or domain requirement it protects.
- Evidence: source location and whether the claim is a static obligation, observed behavior, or an untested hypothesis.
- Recommendation: retain, gate, repair, or retire, with quality risks and unresolved evidence needs.

## Size diagnostics

Lines, words, headings, and rule counts may be useful context; measure them only when relevant to the requested audit. Size alone is not a failure threshold, and prose duplication is not a reason to introduce an orchestrator or subagent. Do not read private observation logs merely to populate a standard metrics table.

## Health indicators

Prioritize broken references, conflicting obligations, unsafe or missing stop conditions, unsupported work expansion, and actual loader/tool incompatibilities. Distinguish local formatting conventions from runtime requirements. A clean metadata check does not prove effective behavior, and a long on-demand reference is not necessarily unhealthy.

## Output modes

For a named skill, report scoped findings with evidence and tradeoffs. For a requested fleet audit, use a concise table over that set; the installed fleet is normally under `~/.agents/skills/`. If scope is unclear, ask once rather than assume every installed skill is in scope. No supported issue means exactly that—not a universal green health claim.

## Rules

- NEVER modify files, notes, or source-owner installations during this diagnostic.
- Use actual source/evidence and mark untested behavior uncertain; reuse still-applicable findings rather than inventing metrics or repeating unchanged investigation.
- Respect the explicit scope, source ownership, and privacy boundaries. Do not run model trials or create follow-up tasks without authorization.
