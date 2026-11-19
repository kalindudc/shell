---
description: Move every model the dotfiles select to the newest model in the same line, then live-test each change
---

Update the models the dotfiles select to the newest release in the same line. When $ARGUMENTS is given it narrows the run, for example `gpt only` or `sol to gpt-6.3-sol`; otherwise cover every model.

## 1. Learn what is available

1. Refresh pi's catalogs with `pi update --models`, then save `pi --list-models` to a scratch file (`$BB_THREAD_STORAGE` in bb, `/tmp` otherwise). Only a model that pi lists can be a target.
2. Read release order and prices from `~/.pi/agent/llm-catalog/catalog.json`: each entry in `data` has `id`, `created`, `taxonomy` (family, major, minor, tags) and each provider's `pricing`. `~/.pi/agent/models-store.json` holds pi's cost card, including the higher tier above 272K input tokens.
3. A line is a vendor, a family and a tier: GPT Sol, GPT Terra, GPT Astra, GPT Luna, Claude Opus, Claude Sonnet, Claude Fable, Kimi, GLM. The newest model in a line has the highest major.minor, then the latest `created`.

## 2. Find every reference

Search the dotfiles repo, `~/src/github.com/kalindudc/shell`, with hidden files included: `rg -n --hidden -g '!.git' -g '!*lock*'`. Also search the live config the repo does not track: `~/.pi/agent/settings.json` (`defaultProvider`, `defaultModel`, `enabledModels` and the keys of `compaction.modelOverrides`). Look for model ids (`gpt-`, `claude-`, `kimi-`, `glm-`, `gemini-`, with and without a `provider/` prefix) and display names such as "GPT-6.1 Sol" or "Claude Opus 5.5". Skip session logs, lockfiles and catalogs.

Sort each hit into one of two kinds:
- Selector: a line that picks the model something runs on, such as a persona's `model:`, a seat in `critics.yml`, a settings key, a table or sentence telling agents which model to use, or a description naming a persona's model.
- Record: a dated measurement, price, benchmark, cost incident or decision history, such as "68 s on 2026-11-02", "$0.03 a call" or "the person's choice on 2026-11-11". NEVER edit a record: it describes the model it was taken on. When you move a selector that sits next to records, add one dated line saying those records were taken on the old model.

## 3. Pick each selector's target

- Stay in the line: Sol stays Sol and Opus stays Opus. A newer model in another line or under a new name is not an update; list it as a candidate in the report and leave the selector.
- Keep the provider variant (`openai-1m/` stays `openai-1m/`, `openai-flex/` stays `openai-flex/`) and the thinking level. For GPT Sol, use the `openai-1m` variant whenever pi lists one: the user chose its 1M-token window over the 272K one on 2026-11-18.
- Compare the old and new prices in the catalog. Ask before switching, naming both prices, when the new model costs more, is a preview, or is in the catalog but not in `pi --list-models`.
- Rules such as "never swap a seat" in `critics.yml` bind agents that read the roster. This command updates the roster itself, so it may move a seat to the newer model in its line.

## 4. Apply and check

Edit only selectors, with one batched edit per file. Then check that `rg` finds no selector left on an old model, that each changed YAML or JSON file still parses (`ruby -ryaml -e 'YAML.load_file(ARGV[0])' <file>`, `python3 -m json.tool <file>`), and that `pi --list-models <id>` lists every target.

## 5. Report bb settings, change none

bb's server settings are not dotfiles. Read them and NEVER change one without the user's yes for it:
- Plugin settings: run `bb plugin list --json`, then `bb plugin config <id> --json` for each plugin, and search the values for model ids. Loom's `plannerInstructions` names the worker and reviewer models.
- Each project's default model for new threads: `sqlite3 -readonly ~/.bb/bb.db "select p.name, d.model, d.reasoning_level from project_execution_defaults d join projects p on p.id = d.project_id"`. The user changes these in bb's model picker for that project.

List each with its current model, the proposed target and where to change it.

## 6. Live-test every change

Send one `spawn` call with one task per changed selector:
- For a persona, set `agent` to it.
- For a critic seat, set `model` and `thinking` from its entry and no agent, the way the critique skill spawns critics.

Each child runs `printenv PI_PROVIDER PI_MODEL`, makes one small read-only tool call and replies in fixed `KEY=value` lines. A child passes when it reports the target provider and model. For pi's default model, run `pi -p --no-session --no-tools --mode json "Reply with the single word: ready"` and read `provider` and `model` from the assistant's `message_end` event.

When a selector moved to a larger context window, offer to prove the window once; run it only on the user's yes, since it cost $1.76 on 2026-11-18. Put a needle line in a file of about 350K tokens and run `pi -p --no-session --no-tools --mode json --model <target> --thinking low @<file> "<question about the needle>"`. It passes when the reply finds the needle and the usage shows more than 272K input tokens.

## 7. Report

Show a table of the changes (file, old model, new model), then the records you left alone, the bb settings waiting on a decision, the test results, and any candidates from other lines.

## Rules

- NEVER commit; the user commits.
- NEVER change bb plugin settings or project defaults without the user's yes.
- NEVER edit a record line.
- NEVER cross a line or a vendor, or drop a provider variant or thinking level.
- ALWAYS live-test every changed selector before reporting success.
