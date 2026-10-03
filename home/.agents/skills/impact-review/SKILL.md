---
name: impact-review
description: Draft evidence-based performance self-reflections and peer reviews from GitHub, Slack, and org sources, scored against the review statements in a private org rubric with a bool classifier. Use when the user asks for an impact review, self-reflection, performance review, a peer review of a colleague, or how to rate someone. Do NOT use for code-review "impact" (blast radius) analysis.
---

# Impact Review

## Goal

Produce a paste-ready draft for the org's review tool (`rubric.tool`) that matches the CURRENT form exactly, where every claim and rating traces to linked evidence. Two modes:

- `self`: the self-reflection, one section per entry of `rubric.forms.self` (e.g. impact examples, "what would unlock", one rating per dimension)
- `peer <name>`: a peer review, one section per entry of `rubric.forms.peer` (e.g. one rating per dimension, a choice question, an optional comment)

The classifier does recall at scale (hundreds to thousands of PRs and threads). You do the judgment: read the top evidence, verify it, and write.

## Org rubric

The skill is a generic engine plus a private org pack. `rubric` below means the pack's JSON.

- Engine (tracked): this file, `scripts/`, and `references/engine.json`, the org-neutral classifier questions (`substantive` gate, `outcome`, `ai`, `reach`, `concern`) and source labels.
- Org pack (gitignored, REQUIRED): `private/rubric.json`, plus org-only collectors in `private/adapters/`. Scripts fail loudly without it. To start, copy `references/rubric.example.json` (a fictional org that shows every field) and fill it in from the org's published review docs.
- NEVER copy pack content (org, program, or tool names, form text, cycle dates, ids, colleague names) into tracked files. Keep examples generic.
- Fields you read: `tool`, `cycle`, `forms` (`manager` is context only), `categories`, `principles`, `references`, `reverify`, `notes`.
- Fields `impact.py resolve` merges into the classifier question set: `org`, `model`, `dimensions` (form wording, classifier question, shortfall), `extra_questions` (with an optional `report` heading and `peer_only`), `sources`.
- Collector config: `github.owner` (gh-* default), `slack` (spread into `slack_collect.js`), `people` (subject resolution), `collect` (org collectors).

## Rules

- ALWAYS start by loading `private/rubric.json` and running its `reverify` steps. If the form changed, update the pack first (`forms`, `dimensions`, `verified`).
- NEVER fabricate or embellish. Every example, number, and rating rationale MUST link to an item in `evidence.md` or to something the user told you.
- NEVER submit anything to the review tool (`rubric.tool`), post to Slack, or DM anyone. Drafts only.
- Peer reviews are anonymous: NEVER quote DMs or traceable phrases in peer drafts. Paraphrase behaviour.
- Judge only the window in `rubric.cycle`. Collect from 30 days before it (see "Cycle and buffer"), but NEVER count or cite buffer-dated items as this cycle's impact.
- ALWAYS save every review in cortex: one task per subject per cycle, in the `impact-review` lane, with the cycle dates in the title (see "Cortex persistence"). The cortex task is the durable record; the run dir is scratch.
- Classifier probabilities are not ratings. "none" signal means "no evidence collected", not "rate 1". Say so instead of guessing.
- Differentiate ratings. Use the "Rating anchors" (Draft step) and leave the final number to the user.
- Plain words, short sentences, no hype. Use honest approximations ("~30%"), not invented precision.
- Keep raw data under the cycle dir only: each run's `raw/` and the shared `_slack_cache/`. When the cycle's reviews are done, offer to delete both; they contain DM text.

## Layout

```
~/.agents/tmp/impact-review/<start>_<end>/
  _slack_cache/                (sensitive; raw thread text + user ids, shared by every run in the cycle)
  <self|peer-slug>/
    raw/*.md (org collector dumps)   raw/slack/*.jsonl   (sensitive)
    questions.json         (resolved: impact.py resolve)
    items/*.jsonl          shards/*.jsonl      results/*.jsonl
    evidence.md            summary.json        draft.md
```

`~/.agents/tmp` is gitignored (repo `.gitignore` `tmp/`). Scripts live in `~/.agents/skills/impact-review/scripts/`; call `impact.py` with `python3`.

## Cycle and buffer

- A cycle lasts `rubric.cycle.months` months. Its id is the official window, `<start>..<end>` (e.g. `2026-01-01..2026-06-30`), taken from `rubric.cycle` after the re-verify step. If the org has not published the window yet, derive the months that end on the cycle close, set `cycle.status` to `derived`, and mark the cortex task `derived` until the org confirms it.
- The collection window is `<start - 30 days>..<end>`. Pass the buffered start to every collector: the org collectors' start date, `gh-* --start`, and Slack `oldest`. The buffer catches work that started before the window and landed inside it: a PR opened before the window and merged inside it, a thread started before the window with the subject's replies inside it, or a rollout planned before the window and shipped inside it.
- Collectors date each item by when the subject's contribution landed: PR merge, the subject's latest review, or the subject's latest Slack message in the thread. `aggregate --start <window start> --end <window end>` keeps buffer-dated and post-window items out of every count and lists buffer items separately as context.
- Buffer-dated items are context only: they belong to the previous cycle, so NEVER count or cite them. Nothing after the window end counts either; that work belongs to the next cycle.

## Cortex persistence

Follow the cortex skill's `recipes/persistence.md` for mechanics. This skill fixes the following.

- Lane: always `impact-review`. Never derive it from the repo. `cortex add` creates the lane if it does not exist.
- Granularity: one task per subject per cycle. A self-reflection is one task, and each peer review is its own task.
- Title: `Impact review <start>..<end>: self (<Full Name>)` or `Impact review <start>..<end>: peer (<Full Name>)`, e.g. `Impact review 2026-01-01..2026-06-30: peer (Jane Doe)`.
- Tags: `cycle-<start>_<end>` (e.g. `cycle-2026-01-01_2026-06-30`; tag names cannot contain dots) plus `self` or `peer`.
- Find or create, never duplicate. First run `cortex ls -l impact-review -t "cycle-<start>_<end>,<self|peer>" --json` and match the subject's name in the title. If a task matches, resume it. Otherwise create one:
  `cortex add "<title>" --lane impact-review --status open -t "cycle-<start>_<end>,<self|peer>" --as <author tag> --body-file <file> --json`
  Under pi, the author tag is the session's `pi-<uuid>` tag from cortex memory. Post every later update with the `cortex_update` tool.
- Previous cycle: look up the same subject's task from the prior cycle (`cortex ls -l impact-review -t <self|peer> --json`). Read its "unlock" answer and Decisions to see what changed and whether past asks were followed through. NEVER carry a claim forward without fresh evidence from this window.
- Body: rewrite it with `cortex edit <id> --body-file <file>` at each milestone (scoped, aggregated, drafted, revised). Use these sections:

  ```markdown
  ## Cycle
  - Cycle: <label>, window <start>..<end> (official | derived), collected <start-30d>..<end>
  - Subject: <Full Name> (<role>), mode: self | peer
  - Due: <deadline from rubric.cycle.deadlines>
  ## Draft
  <draft.md verbatim, once written>
  ## Evidence
  - Coverage: items per source, classified, unclassified, buffer-only
  - Statement signal table (copied from evidence.md)
  - Cited evidence: the links used in the draft
  ## Decisions
  - Ratings chosen and why; the user's reflection answers (self) or how closely they worked together (peer)
  ## Next
  ## Files
  - <run dir>
  Verified: YYYY-MM-DD
  ```

- Status: `open` while collecting and drafting. Set `review` when the draft is in the body and handed to the user. Set `blocked` only when progress waits on a decision only the user can make (the data cannot answer it). Set `done` ONLY after the user confirms they submitted the review in the review tool (`rubric.tool`).
- Revisions: never edit a `review` task without the user's say-so. A user asking for changes counts as approval. Flip the task to `open` with `cortex_update`, edit the body, then set it back to `review`.
- Privacy: the body holds the draft, ratings, links, and the user's answers. NEVER put raw Slack text, DM quotes, or the `colleague-N` mapping in it.

## Running templates

`classify.js` and `slack_collect.js` are codemode scripts. Run them from disk with overrides instead of pasting:

```js
// @options: {"max_output_tokens": 3000, "timeout_ms": 7200000}
const src = (await tools.bash({ command: "cat ~/.agents/skills/impact-review/scripts/classify.js", timeout: 10 })).output;
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
return await new AsyncFunction("tools", "models", "P_OVERRIDE", src)(tools, models, { dir: "<run dir>", /* ...keys from DEFAULTS */ });
```

All paths in `P` must be absolute. For `slack_collect.js`, read the pack in the same script and spread it: `{ ...rubric.slack, cache_dir, channels, ... }`.

## Process

### 1. Scope

1. Load the pack and run `rubric.reverify` (see Rules). Fix the cycle id `<start>..<end>`, the label (`rubric.cycle.label`, e.g. `2026-H1`), and the collection window `<start - 30 days>..<end>`.
2. Resolve the mode. For `peer`, accept one name or a list. For a list, follow "Batch peer reviews" below: batch the mechanical steps, keep judgment per subject.
3. Call `slack_who_am_i` (required before any Slack tool). It gives the reviewer's Slack id.
4. Resolve the subject as `rubric.people` describes: full name, title, team, GitHub login, and Slack id. Role string = title + team. Note when the subject is the reviewer's manager or direct report.
5. Create the run dir, then resolve the question set: `python3 scripts/impact.py resolve --out <run>/questions.json`.
6. Find or create the cortex task (see "Cortex persistence"). Fill the `## Cycle` section, and read the subject's previous-cycle task if one exists.

### 2. Collect

Run the independent sources in parallel where possible. Record counts per source. Every start date, `--start`, and `oldest` below is the buffered collection start; every end is the window end.

1. Org collectors: run each `rubric.collect` entry whose `modes` include the current mode, following its `steps`. Each writes `items/<name>.jsonl` in the item schema (see the `impact.py` docstring) and may keep its raw dump under `raw/`.
2. GitHub (`gh` rate limits are handled; runs take minutes; `--max` defaults to 1000 because 300 silently truncated a real run). The org comes from `rubric.github.owner`; `--owner` overrides it, and `''` searches all orgs:
   - self: `impact.py gh-reviews --user <login> --label <First> --start <d> --end <d> --out items/gh_reviews.jsonl` (the reviews you gave others, a strong signal for craft and expansion dimensions)
   - peer, first-hand: `impact.py gh-prs --user <peer> --involves <you> --reviewer-label REVIEWER ...` (their PRs you engaged on) and `impact.py gh-reviews --user <peer> --author <you> ...` (their reviews of your PRs)
3. Slack (the slowest source; ~1s per thread unthrottled, 30-70s under rate limits; a 24-channel self run took ~3.7h):
   - Pick channels with the user. Self: team channels, project and incident channels, help channels you answer in, top DMs. Peer: your DM with them plus shared team and project channels.
   - Ids must be C/G/D. Find DM ids yourself; never ask the user for permalinks: `slack_read_channel({channel_id: <user id>, limit: 1})` in markdown mode (no `format`) returns a `Channel: DM (D…)` header. `format: "json"` rejects user ids.
   - Run `slack_collect.js` (see Running templates) with `...rubric.slack` (workspace and tool names), `cache_dir` = `~/.agents/tmp/impact-review/<start>_<end>/_slack_cache`, `channels`, `oldest` (buffered start), `latest` (the day after the window end, exclusive), and either `subjects: [{uid, s, dir: <run>/raw/slack}]` or the self shorthand `dir` + `subject_uid` + `s`. Peer mode adds `reviewer_uid` and `firsthand_only: true`.
   - The cache is per cycle: each channel is paged once and each thread fetched once, for the self run and every peer. Only threads a subject took part in are fetched (from `reply_users`; with `firsthand_only`, only threads you are also in, plus DMs). Adding channels where nobody relevant posted costs only paging.
   - Thread reads take ~30-70s each under rate limits, so start it early. It backs off on rate limits and transient errors until `budget_minutes` (default 100) is spent, then returns `{limited:true}` with what is cached already built into items. Re-run the same call until `limited:false`.
4. Ask the user for evidence these sources miss: incidents led, interviews, mentoring, talks, docs, and decisions in meetings. Add each to `items/notes.jsonl` as `{id, source:"note", url, date, title, workstream, text:"<First>: ..."}`.

### 3. Classify

1. `python3 scripts/impact.py shard items raw/slack --out shards --size 80`. `classify.js` skips any shard whose `results/<shard>.jsonl` exists, so after adding items and re-sharding, `rm -f results/*.jsonl results/*.errors` first (a full re-classify is ~1 minute).
2. Run `classify.js` (see Running templates) with `dir`, `questions` (absolute path to `<run>/questions.json` from `resolve`), `subject`, `s`, `role`, and `mode`. Measured throughput is ~16 items/s (214 items in 13s), so 2,000 items take ~2 minutes. It is resumable and retries failed items. Model cost notes are in `rubric.notes`.
3. Check the returned `errors`. Re-run until 0, or report how many items remain unclassified.

### 4. Aggregate

`python3 scripts/impact.py aggregate --items items raw/slack --results results --mode <self|peer> --label <First> --start <window start> --end <window end> --out evidence.md --json summary.json`

`--start` and `--end` take the official window, not the buffered one. In self mode, add `--pi-sessions ~/.pi/agent/sessions` to count interactive and delegated pi sessions in the window as AI-usage evidence.

After aggregating, write the Coverage and signal table into the cortex task's `## Evidence` section.

`evidence.md` contains:

- coverage by source, with in-window, buffer, and post-window counts
- a signal table per statement: hits, share, rank, distinct workstreams, months, share beyond the team, share with outcomes, suggested rating band
- pace stats computed from dates. The per-item classifier undercounts velocity, so rate any speed or pace dimension from these numbers.
- highlight-candidate workstreams (routine release and bump PRs are ranked lower)
- top evidence per statement, breadth first (one per workstream)
- possible shortfalls
- AI leverage
- one section per extra question with a `report` heading (peer-only ones in peer mode only)
- buffer items (context only, never cited)

Sanity-check before writing: if the coverage looks lopsided (e.g. 0 Slack items), say so and offer to collect more.

### 5. Verify and reflect

1. Read `evidence.md` in full. For each item you plan to cite, re-read the item text and check that the claim holds. Use `gh pr view` or `slack_read_thread` if the excerpt is ambiguous. Drop anything that does not hold up.
2. Self mode: show the user the top workstreams and signal table, then ask:
   - What are you proudest of, and what was hard about it?
   - What fell short, or what would you do differently? (feeds "unlock" and ownership dimensions)
   - Is anything missing from the data?
3. Peer mode: do not ask how closely you worked together. Infer it from first-hand counts: shared Slack threads, DM messages, their PRs you engaged on, their reviews of your PRs, your reviews of their PRs (self run's `gh_reviews.jsonl`), and shared meetings on your calendar. State the closeness and its basis under Decisions. If first-hand evidence for a statement is thin, suggest "I don't know" or a conservative rating rather than inflating.

### 6. Draft

Write `draft.md` by rendering the mode's form (`rubric.forms.self` or `rubric.forms.peer`) entry by entry, in order, then print it with the path. Copy it into the cortex task's `## Draft` section, record the chosen ratings and the user's answers under `## Decisions`, and set the task to `review`.

Header:

- self: `# Self-reflection: <cycle label> (<window>)`, then `> Draft. Evidence in evidence.md. Edit into your own voice before pasting into <rubric.tool.name>.`
- peer: `# Peer review: <Name> (<cycle label>)`, then `> Draft for the reviewer only. Ratings are suggestions; rationales are for you, not to paste verbatim.`

Each form entry becomes a `## <text>` section (fill in `[NAME]`), rendered by `kind`:

- `examples`: up to `max` examples, each:

  ```markdown
  ### 1. <Outcome-first title>
  Shipped: <1-2 sentences. What exists now that did not before.>
  Impact: <1-2 sentences. What got better, for whom, how much. Mention AI leverage here if real.>
  Evidence: <2-4 links>
  ```

- `unlock`: 2-4 sentences. Concrete asks tied to the shortfalls and the user's answers. Not complaints.
- `ratings`: a `## Ratings` section with one row per dimension, using its `self` or `peer` wording verbatim. In peer mode the last header reads `Why (first-hand, one line + link)`.

  ```markdown
  | Statement | Suggested | Why (one line + link) |
  |---|:-:|---|
  | <dimension wording> | | |
  ```

- `choice`: the pick is the user's call. Give 1-2 sentences of first-hand evidence from the section of `evidence.md` for the entry's `evidence` question (e.g. trust and resourcefulness). Suggest an option only if `options` is set or the user supplied them.
- `text`: a short answer grounded in the evidence or the user's answers.

Peer drafts end with:

```markdown
## Optional comment (only if the form has a box)
Strength: <1-2 sentences, specific>. Unlock: <1 sentence, constructive>.
```

Example selection: choose up to `max` highlight workstreams with the strongest weighted evidence, the widest reach, and observable outcomes. Merge related workstreams into one story (e.g. a project and its follow-up PRs). Write title, then shipped, then impact. Aim for under 120 words per example.

Rating anchors (skill convention, not official): on a 1-5 `forms.scale`, treat 3 as "true some of the time", 4 as "consistently true with strong examples", and 5 as "exceptional; a calibrator would point to it as the standard". Map other scales proportionally. Differentiate across the dimensions: all top scores read as uncalibrated and weaken the review. When `rubric.categories` exists, use it only to sanity-check how strong the evidence is overall; categories are the manager's call, not the reviewer's.

### 7. Wrap up

- Report counts (items per source, classified, unclassified, buffer-only), the cortex task id, the draft path, and anything unverified.
- When the user says the review is submitted, post a `cortex_update` with status `done`. Until then, leave it in `review`.
- Offer to delete `raw/` and, once every review in the cycle is done, the cycle's `_slack_cache/` (both hold DM content). Do it only on confirmation.
- Append observations to `SKILL_NOTES.md` (what broke, thresholds that misfired, sources that were missing).

## Batch peer reviews

Use this when the user names several peers. Batch the mechanical steps; keep judgment per subject. Each subject still gets its own run dir, cortex task, evidence, and draft.

1. Scope once. Load the pack, run `rubric.reverify`, and call `slack_who_am_i` once for the batch. Resolve every subject in one codemode call as `rubric.people` describes (title, team, GitHub login, Slack id). Label each subject `s` with their first name; use full names if two share one. Flag anyone who is the reviewer's manager or direct report so the user can confirm the form lists them as a peer request. Run `impact.py resolve` into each subject's run dir.
2. Cortex once. One `cortex ls -l impact-review -t "cycle-<start>_<end>,peer" --json`, match every subject by name, create only the missing tasks (one per subject), and read each subject's previous-cycle task.
3. Hands-free by default: the user wants to keep working, not answer questions. Do not ask for closeness, DMs, or channels. Infer closeness from the data (see 5.3), discover each subject's DM id yourself (see Collect step 3), and reuse the self run's channel list plus the DMs. The pick for the form's `choice` question is the user's: draft the evidence for it, not the choice. Ask only when the data cannot answer, e.g. a subject with no first-hand items at all.
4. Collect in parallel lanes. Start GitHub and Slack first; they are the long poles.
   - GitHub: one background shell loop, run sequentially because every subject shares the `gh` rate limit: `gh-prs --user <peer> --involves <you>` and `gh-reviews --user <peer> --author <you>` per subject, each with its own log.
   - Slack: ONE `slack_collect.js` call for all subjects: `...rubric.slack`, `subjects: [{uid, s, dir}, ...]`, `reviewer_uid`, `firsthand_only: true`, the cycle `cache_dir`, and `channels` = the union of shared channels plus every subject's DM. Threads already cached by the self run are reused. Re-run until `limited:false`.
   - Org collectors: run each `rubric.collect` entry for every subject, following its batch steps. These items show what the subject shipped; they are context, not first-hand.
5. Classify in one codemode call that loops the classify template over subjects (per-subject `dir`, `questions`, `subject`, `s`, `role`, `mode: "peer"`). Aggregate in one bash loop.
6. Verify and draft per subject; judgment does not batch, but it parallelizes. For 3+ subjects, spawn one minion per subject (mid/premium model, read-only, ~30 tool calls) with the peer form rendering rules, the rating anchors, the first-hand-only and anonymity rules, and the run dir; each writes `draft.md` and `decisions.md`. When a subject has few first-hand items (under ~5 for a statement), suggest "I don't know" or a conservative rating.
   Then calibrate across the batch yourself: keep top ratings rare and backed by sustained first-hand evidence, lower top ratings that rest on one episode or one PR (note the alternative in the rationale), and privacy-scan every draft (no quote marks, no `colleague-N`, no links or numbers in the optional comment). Write each cortex body yourself; do not copy minion `decisions.md` into cortex, since it may carry DM-derived detail.
7. Present all drafts together with a summary table (subject, closeness, suggested ratings, choice evidence, first-hand item count), then set each task to `review`. Set each to `done` only when the user confirms that subject's review was submitted.

## References

- `references/engine.json`: org-neutral classifier questions (`substantive` gate, `outcome`, `ai`, `reach`, `concern`) and generic source labels
- `references/rubric.example.json`: a fictional org pack that documents every rubric field; copy it to `private/rubric.json` to start
- `private/rubric.json` (gitignored): the org pack (see "Org rubric")
- `private/adapters/` (gitignored): org-only collectors referenced by `rubric.collect`
- `scripts/impact.py`: `resolve`, `gh-reviews`, `gh-prs`, `slack-plan`, `slack-build`, `shard`, `aggregate`
- `scripts/classify.js`, `scripts/slack_collect.js`: codemode templates (run from disk with `P_OVERRIDE`, see Running templates)
- cortex skill `recipes/persistence.md`: body-file, attribution, and revision mechanics for the `impact-review` lane
- `SKILL_NOTES.md`: known edge cases. Read it before running.
