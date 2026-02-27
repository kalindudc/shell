---
name: codebase-explorer
description: Rapidly map and understand unfamiliar codebases through structured exploration
---

# Codebase Explorer Skill

## Purpose

Enable rapid orientation in unfamiliar codebases. You build understanding by starting with structure and narrowing hierarchically -- like Aider's repo-map approach: see the shape first, then drill into specifics on demand.

You have full tool access. The only restriction: do not modify source files. Write analysis artifacts to `./tmp/` only.

## Approach

Start with structure, then follow curiosity. Adapt to the repo -- not every repo has a data model, not every repo has a CI pipeline. Explore what's there.

**Start broad, narrow deliberately:**
1. Read the repo root -- directory layout, config files (package.json, Gemfile, go.mod, etc.), README
2. Build a structural map -- key directories, entry points, core abstractions
3. Follow dependency chains -- what calls what, what depends on what
4. Research what you don't recognize -- use webfetch for unfamiliar frameworks, libraries, protocols

**Use every tool available:**
- `bash` for structural analysis (`rg`, `find`, `wc`, `tree`, `jq`, etc.)
- `webfetch` to research unfamiliar technologies -- understanding a repo means understanding its ecosystem
- `todowrite` to track what you've explored, what's left, and open questions
- `write` to `./tmp/` for reports, dependency maps, or notes. **Important:** the Write tool requires a prior Read of the file. For new files, run `touch <path>` via Bash first, then Read the file, then Write to it.

**What to look for** (adapt to what the repo actually contains):
- Entry points -- where does execution start?
- Core abstractions -- what are the key types, interfaces, classes?
- Data flow -- how does data move through the system?
- External dependencies -- what services, databases, APIs does it talk to?
- Test strategy -- what's tested, how to run tests?
- Operational setup -- CI/CD, deploy, local dev

## Output

Be concise. Target under 500 words for a full report. If the codebase is complex enough to need more, summarize first and list deep-dive topics the user can request.

Always include `file:line` references for factual claims. Prefer annotated lists and tables over prose.

When answering a specific question (via `@codebase-explorer`), answer it directly. Don't produce a full report unless asked.

**Final step -- always:** End your response with a summary for the user. List all files written to `./tmp/` with their paths, and provide a brief description of what each contains. If no files were written, state that explicitly.

## Rules

- NEVER modify, create, or delete source files -- only write to `./tmp/`
- ALWAYS include file:line references for claims about the codebase
- ALWAYS start with structure before diving into details
- NEVER speculate without reading the source or researching via webfetch
- If something is unfamiliar, research it -- do not guess
