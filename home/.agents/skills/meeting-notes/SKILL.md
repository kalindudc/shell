---
name: meeting-notes
description: Extract topics, per-topic brief summaries, and topic-grouped action items from a Google Doc meeting notes link. Supports multi-tab Docs (including Gemini auto-generated Notes + Transcript tabs) and any linked Google Sheets. Read-only — never modifies the source document.
---

# Meeting Notes Extractor

## Purpose

Given a Google Doc URL (meeting notes, possibly with a Gemini-generated Transcript tab and/or linked Sheets), produce a structured Markdown report containing:

1. Topics discussed, each with a brief summary
2. Action items grouped as bullets under the relevant topic
3. An overall meeting summary
4. Open questions and follow-ups

## HARD RULES (read carefully — these are not optional)

### Read-only access
- NEVER issue any Google API call other than `GET`. NEVER `POST`, `PUT`, `PATCH`, `DELETE`, no `:batchUpdate`, no `files.update`, no `files.copy`, no `files.delete`, no `permissions.*`, no `revisions.*`.
- NEVER modify the source Google Doc in any way — no comments, no edits, no share changes, no moves, no rename, no trash.
- All network access goes through `scripts/meeting-notes.py`, which has a hardcoded whitelist of hosts, paths, and HTTP methods, plus a pre-flight self-check against forbidden write patterns.
- If you need a capability the script doesn't provide, STOP and ask the user. Do NOT add ad-hoc `curl` calls or edit the script to bypass guards.

### Fail loud
- If `gcloud` is missing, the auth token is empty, scopes are insufficient, or the doc returns 401/403/404 — STOP immediately and surface the exact error to the user. Do NOT silently fall back to partial extraction or try a second tool.

### Evaluate everything
- Process ALL tabs (including nested `childTabs`) and ALL linked/embedded Google Sheets. Per-sheet and per-tab caps live in the script; if a cap is hit, surface the warning verbatim — do not paper over truncation.

### Timeout guard for all shell scans
- Any `find`, `grep`, `rg`, or similar filesystem scan invoked by this skill MUST be wrapped in `timeout <N>` with a bounded scope (`-maxdepth`, an explicit path, etc.). Never scan `/` or `$HOME` unbounded.

## Inputs

- Required: a Google Doc URL from `$ARGUMENTS`. Example: `https://docs.google.com/document/d/<ID>/edit?tab=t.xxx`.
- If `$ARGUMENTS` is empty or doesn't contain a recognizable Google Doc URL (regex: `https?://docs\.google\.com/document/d/[a-zA-Z0-9_-]+`), ask the user for the URL.
- Do NOT accept local file paths, raw text, or other inputs. Only a URL.

## Process

### 1. Pre-flight

1. Confirm the URL matches the Google Docs regex above. If not, ask the user.
2. Check `timeout 5 which gcloud` — if missing, STOP with: "`gcloud` CLI not found. Install from https://cloud.google.com/sdk/docs/install."
3. Check `timeout 10 gcloud auth print-access-token` returns a non-empty token. If it fails, STOP with the exact stderr and tell the user to run `gcloud auth login`.
4. Extract the document id from the URL (regex: `/document/d/([a-zA-Z0-9_-]+)`). Derive a short slug from the id's first 8 chars if the title isn't known yet.
5. Create output directory:
   ```bash
   DATE=$(date -u +%Y-%m-%d)
   mkdir -p "./tmp/meetings/${DATE}-<slug>"
   ```
   The slug will be replaced after step 2 with a doc-title-derived slug (lowercase, kebab-case, max 40 chars). For now use the id prefix.

### 2. Fetch the bundle

Invoke the orchestrator script:

```bash
timeout 90 python3 ~/.agents/skills/meeting-notes/scripts/meeting-notes.py \
  --url "<URL>" \
  --output-dir "./tmp/meetings/<date>-<slug>" \
  --verbose
```

The script:
- runs a pre-flight self-check (forbidden-write-pattern grep on its own source)
- validates auth + scopes via Drive `about`
- fetches the Doc with `?includeTabsContent=true`
- walks `tabs[].childTabs[]` recursively
- extracts per-tab plaintext + hyperlinks
- detects linked Google Sheets and fetches metadata + values for each
- writes `bundle.json`, `raw-doc.json`, and `raw-sheet-<id>.json` per sheet

If exit code is non-zero:
- exit 1 → auth / permission / not-found error. STOP and show the user the stderr.
- exit 2 → self-check tripped. This is a bug in the skill itself. STOP and show the user the stderr; do NOT attempt to work around it.

If exit code is 0, proceed. Re-slugify the output dir based on the fetched title if needed (optional polish — only if `os.rename` is safe).

### 3. Classify tabs

Read `bundle.json`. For each tab:
- `isTranscript=true` in the bundle is a HINT, not a filter. Gemini-generated Notes tabs often contain timestamp deep-links to the recording and will be flagged. Trust content over the heuristic.
- Apply your own classification:
  - `Transcript` ≈ verbatim speaker turns with timestamps, long-form, few headings.
  - `Notes` ≈ structured summary with headings like "Summary", "Decisions", "Action Items", few or no speaker attributions.
  - Other tabs (agenda, appendix, roadmap, etc.) should be included too — don't discard.
- If there is BOTH a Notes tab and a Transcript tab, reconcile: the Notes tab carries the intent; the Transcript tab backfills missed items and provides quotable evidence.

### 4. Extract topics + action items

Scan all tab text (and sheet rows, if any) and produce:

- A flat list of topics. A topic is a coherent subject discussed in the meeting. Prefer the Notes tab's headings when present.
- For each topic: a 2-4 sentence summary capturing decisions, trade-offs, and context.
- For each topic: action items as bullets directly under the topic heading.

Action-item extraction rules (generous mode):

- Include clear commitments with an owner + commitment verb (e.g., "@alice will write the RFC by Monday").
- ALSO include tentative commitments ("I'll probably take a look", "let me explore X"), tagged `[low]` before the item text.
- For each item, try to capture: owner (handle, name, or `Unassigned`), the action, and a due date if mentioned. Use `—` when missing.
- Dedupe items that appear in both Notes and Transcript — prefer the more specific phrasing.
- Cite the source tab and a locator (section heading from Notes, or `HH:MM:SS` timestamp from Transcript) in parentheses after the item.

### 5. Write the report

Write to `./tmp/meetings/<date>-<slug>/meeting-notes.md`:

```markdown
# <Doc Title>

**Source:** <URL>
**Fetched:** <ISO-8601 UTC>
**Account:** <email>
**Tabs processed:** <list of tab titles>
**Sheets processed:** <list of sheet titles, or "none">

---

## Summary

<3-6 sentence overall recap of the meeting: what was discussed, what was decided, what's outstanding>

---

## Topics

### <Topic name>

<2-4 sentence topic summary>

- <action item> (@owner, due <date>, tab=<Notes/Transcript>, §<section or HH:MM:SS>)
- [low] <tentative action item> (Unassigned, —, tab=Transcript, 00:42:10)

### <Next topic>
...

---

## Open Questions / Follow-ups

- <unresolved question or deferred decision> (tab=<source>, <locator>)

---

## Sources Processed

- Tab: Notes (9,764 chars)
- Tab: Transcript (46,979 chars)
- Sheet: "<name>" (<id>, <row count> rows)

---

## Warnings

<Verbatim warnings from bundle.json, or "none">
```

Formatting rules:
- Topics use H3 (`###`).
- Action items are bullets directly under the topic, never in a table, never in a separate section.
- Each action item ends with a parenthesized source citation so the user can verify it.
- `[low]` appears at the start of the bullet for tentative items.
- If the Notes tab has an explicit "Action Items" section, preserve its owner/item mapping but distribute items under the relevant topics. If an item doesn't clearly map to a topic, put it in a topic called "Cross-cutting".

### 6. Recap to stdout

Print a short inline recap after writing the file:

```
Wrote: ./tmp/meetings/<date>-<slug>/meeting-notes.md
Topics: <count>
Action items: <count> (<low count> tentative)
Open questions: <count>
Warnings: <count>
```

## Output files

- `./tmp/meetings/<date>-<slug>/meeting-notes.md` — the human-readable report (primary deliverable)
- `./tmp/meetings/<date>-<slug>/bundle.json` — structured extraction from the script
- `./tmp/meetings/<date>-<slug>/raw-doc.json` — raw Docs API response
- `./tmp/meetings/<date>-<slug>/raw-sheet-<id>.json` — raw Sheets API responses per linked sheet (if any)

## Rules

- NEVER issue non-GET API calls to Google services
- NEVER modify the source document, its metadata, or its sharing
- NEVER add ad-hoc `curl` / `wget` calls — only the orchestrator script talks to Google
- NEVER silently fall back on auth/permission errors — STOP and tell the user
- NEVER scan the filesystem without `timeout` + bounded scope
- ALWAYS evaluate all tabs (including nested `childTabs`) and all linked Sheets
- ALWAYS cite source tab + locator for every action item and open question
- ALWAYS surface bundle warnings verbatim in the report
- ALWAYS prefer Notes-tab headings for topic names when both Notes and Transcript are present
- ALWAYS tag tentative items with `[low]` (generous extraction mode)

## Self-Improvement

After execution, use the `skill-improver` agent to capture observations in `SKILL_NOTES.md`. Before execution, read `SKILL_NOTES.md` for known edge cases.
