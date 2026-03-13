---
name: performance-review
description: Collect GitHub and project contributions for a time period and synthesize a concise, impact-focused performance review
---

# Performance Review Skill

## Purpose

Collect contribution data from GitHub (and optionally vault-mcp) for a user-specified
time period, then synthesize a narrative-ready self-reflection that highlights impact,
demonstrated skills, and growth. The output should be directly usable in performance
review submissions -- written in the user's voice, focused on "so what?", not a changelog.

## Process

### 1. Determine the review period

- Parse `$ARGUMENTS` for a time period (e.g., "6 months", "2025 H2", "last quarter", "2025-01-01 to 2025-06-30")
- If no period is specified, prompt the user
- Calculate the start date and end date in ISO format (YYYY-MM-DD)
- Determine the period label for the output filename (e.g., "2025-H2", "2025-Q4", "6mo-ending-2026-03")

### 2. Resolve the GitHub user

- Run `gh api user --jq '.login'` to get the authenticated GitHub username
- Confirm with the user if they want to review a different user's contributions

### 3. Collect GitHub contributions

Run sequentially with 10-15s delays between calls to avoid secondary rate limits. After any 403, wait at least 5 minutes. Use `--limit=100` for reviewed-by/commenter searches. Use range syntax for date filters (`START..END`) -- double flags are BROKEN (second silently overwrites first).
Prompt for `--owner=<org>` to scope to a GitHub org if the user works in an enterprise environment.

- `gh api graphql` with `contributionsCollection(from, to)` -- sanity check for commit counts only; never use for PR/review counts (returns 0 for repos without push access)
- `gh search prs --author=<user> --created="START..END" --limit=500 --json title,repository,url,state,createdAt,body,labels`
- `gh search prs --reviewed-by=<user> --created="START..END" --limit=100 --json title,repository,url,labels`
- `gh search prs --commenter=<user> --created="START..END" --limit=100 --json title,repository,url,labels`
- `gh search issues --author=<user> --created="START..END" --limit=500 --json title,repository,url,state,createdAt,labels`
- `gh search commits --author=<user> --author-date="START..END" --limit=500 --json sha,repository,commit`
- Extract `#gsd:<number>` from labels to map GitHub activity to vault GSD projects

### 4. Collect vault-mcp contributions (optional)

Check availability by calling `vault_get_current_user`. If it fails, skip vault and note it in output.

Collection sequence (see Implementation Notes for full tool reference):
1. `vault_get_current_user` -- profile, team, active projects, recent post IDs
2. `vault_get_projects(contributor=<gh_handle>)` for active + `status="concluded", concluded_year=YYYY` per year
3. `vault_get_projects(champion=<gh_handle>)` -- leadership signal
4. `vault_get_project(id, include_activity=true, activity_weeks=<period>)` per project -- activity feed, milestones, success criteria
5. `vault_get_post(post_id)` for user's recent posts -- communication/visibility signal
6. `vault_get_mission(mission_id)` if projects link to missions -- strategic alignment

### 5. Analyze through impact, not activity

Cross-reference GitHub data with vault context. Use `#gsd:<number>` labels as the primary bridge. When vault-mcp is available, treat project activity feeds as the *primary* source for impact narrative; GitHub data provides quantification, vault provides "why it mattered."

The impact formula -- apply to every contribution before writing:
```
[What I did] → [Why it mattered] → [What changed / measurable result]
```
- Group by GSD project (via `#gsd:` labels) then by repo. Prefer vault project names.
- Classify impact (high/medium/low) using: PR complexity, project priority, collaboration scope, champion role, mission alignment.
- Identify the 3-5 strongest examples -- not every example. These become Key Accomplishments.
- Identify 3 Spotlight items the user is most proud of.
- Extract AI usage patterns from tools, workflows, and PR descriptions.
- Note mentorship signals: PR reviews, onboarding help, cross-team contributions.

### 6. Prompt the user for reflection

Before synthesizing, ask the user three questions (present the raw data summary first):
1. What are you genuinely proud of? -- Not just what shipped, but what was hard.
2. What would you do differently with a time machine? -- This becomes the Growth Areas section.
3. What did you learn? -- New skills, new confidence, new ways of working.

Use their answers to shape the narrative. If they skip this, synthesize from data alone but note that the reflection sections will be less personal.

### 7. Synthesize the self-reflection

Writing principles:
- Write in first person. This is the user's voice, not a report about them.
- Every bullet must answer "so what?" -- describe what changed, not just what was done.
- 3 sentences or fewer per impact point. Link to evidence instead of explaining context.
- No corporate cliches, no hype, no filler. If it sounds like a press release, rewrite it.
- Don't fabricate precision. "~30% reduction" is honest. "31.7%" when guessing is not.
- Quantify where possible: latency, error rates, time saved, PRs, repos, people mentored.

## Review Template

Use this structure. Omit sections only if data is truly unavailable.

```markdown
# Self-Reflection: <period>
> Generated on <date> | GitHub: <username> | Vault: [included/not available]
> This is a draft. Edit it to sound like you before submitting.

## Key Accomplishments
[3-5 strongest examples. Each: **[Title]**: what you did -- why it mattered / measurable impact. [Link]]

## Spotlight Work (Top 3)
[Up to 3 pieces of work you're most proud of. 1-2 sentences max each. Include links.]

## AI Integration
[How you used AI tools, what workflows changed, what value it added. Be specific.]

## Contributions by Area
### [Project/Area]
- [Impact-framed contributions with links]

## Job Requirements Self-Assessment
| # | Requirement | Rating (1-5) | Evidence |
|---|-------------|:---:|---|
| 1 | Be exothermic | | |
| 2 | Be resourceful | | |
| 3 | Dedication to craft | | |
| 4 | Effective building | | |
| 5 | Know all the details | | |
| 6 | Make great decisions | | |
| 7 | Quicken the pace | | |
| 8 | Take ownership | | |
| 9 | Tend to the commons | | |
| 10 | AI use | | |

## Growth & Learning
- **Skills**: [New skills developed or deepened]
- **Mindset**: [How your approach evolved]
- **Collaboration**: [How you improved working with others]

## Areas for Improvement
[What happened → What you learned → What you'd do differently. Frame constructively.]

## Goals for Next Period
[SMART goals: Specific, Measurable, Achievable, Relevant, Time-bound]

## By the Numbers
| Metric | Count |
|--------|-------|
| PRs authored | X |
| PRs reviewed | X |
| Issues opened | X |
| Commits | X |
| Repos touched | X |

## Project Ownership (vault-mcp only)
| Project | Role | Priority | Phase | Mission |
|---------|------|----------|-------|---------|
```

## Output

- Write the review to `./tmp/performance-review/<period-label>-review.md`
- Create the output directory if it does not exist
- Copy to clipboard if available (`pbcopy` on macOS)
- Print a brief summary to the user with the file path
- Remind the user: "This is a draft. Read it aloud -- if it doesn't sound like you, rewrite those parts."

## Self-Improvement

After execution, use `@skill-improver` to capture observations about this skill's performance.
Before execution, check `SKILL_NOTES.md` for known edge cases.

## Rules

- ALWAYS resolve the time period before collecting data -- never guess dates
- ALWAYS use `gh` CLI for GitHub data -- never scrape or use unauthenticated APIs
- NEVER fabricate or embellish contributions -- every claim must trace to real data
- ALWAYS quantify achievements where the data supports it
- ALWAYS note when vault-mcp data is unavailable rather than silently omitting
- Prefer impact and narrative over exhaustive listing -- this is a review, not a changelog
- KEEP the output under 10 minute read time
- ALWAYS write in first person, ready for direct use in performance review submissions
- FOLLOW KISS -- if it can be shorter, make it shorter
