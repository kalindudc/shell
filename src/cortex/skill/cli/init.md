# `cortex init`

Initialize the cortex SQLite database under `~/.config/cortex/cortex.db`, create the default `now` lane, and (re)write the embedded skill files at `~/.agents/skills/cortex/`.

## Usage

```bash
cortex init
```

## Args

None. `init` is idempotent on a healthy DB but is destructive to the on-disk skill (see Pitfalls).

## Example

```bash
$ cortex init
✓ initialized /Users/you/.config/cortex/cortex.db
```

After this, both the CLI is ready to use and any AI agent reading from `~/.agents/skills/cortex/` will see the latest cortex skill.

## Pitfalls

- **The skill at `~/.agents/skills/cortex/` is machine-generated.** `cortex init` writes the skill files embedded in the binary. Re-running `cortex init` (or upgrading the cortex binary and running `init` again) **OVERWRITES the skill directory**. Any hand-edits to `~/.agents/skills/cortex/SKILL.md`, `cli/*.md`, or `recipes/*.md` are **LOST**. To customize the skill, edit it in the cortex source repo and rebuild the binary.
- `init` does NOT migrate an existing DB to a new schema. If you have a legacy DB created with an older schema (e.g. the old 200-char summary `CHECK` constraint), use [`cortex reset`](reset.md) to start fresh.
- `init` does NOT start the daemon. Run [`cortex serve`](serve.md) afterwards to bring up the dashboard.
