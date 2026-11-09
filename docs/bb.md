# Syncing a work-free bb setup

`bb.yml` is the portable recipe and the capture allowlist. It restores the personal
parts of the setup through bb's CLI, not by copying its database. Capture refreshes
only what this file already approves. New plugins and setting keys are excluded
until someone reviews and adds them.

This is a configuration sync, not a disaster-recovery backup of the bb server.
It does not preserve conversations, projects, machines, or credentials.

## Everyday use

On the machine whose settings you want to keep, with bb already running:

```sh
task bb:export
task check:leaks
git diff -- bb.yml
```

Review the diff before staging or committing it. Capture replaces `bb.yml`
atomically only after privacy checks pass. It never applies settings, installs
plugins, starts bb, or writes anything to the private companion repo. Export
formatting is generated; keep explanations in this document rather than inline
comments that would disappear on the next capture.

On another machine, pull the reviewed recipe and start bb:

```sh
task bb:plan
task bb
```

The preview prints the commands that would run. It does not start bb or install
its CLI launcher. Apply starts bb if needed, installs missing approved plugins,
and changes the declared settings. A full `./install.sh` also applies the recipe.
The usual dotfile setup still provides the separately tracked agent instructions,
skills, and provider configuration under `home/`.

Both commands need a working `bb` CLI connected to the intended local server.
They use the same CLI connection as ordinary `bb` commands; check `bb status` if
you use multiple servers. They do not use `bb server export` or move a server.

To run without Task:

```sh
ruby src/install.rb --bb-export
ruby src/install.rb --bb --dry-run
ruby src/install.rb --bb
```

Capture the preferred machine first, then pull and apply on the others. There is
no background sync or last-writer-wins conflict resolution. Resolve a Git conflict
in the recipe before applying it.

## If the local Ruby toolchain is broken

The installer needs Ruby's JSON and YAML libraries. A native gem compiled for a
different Ruby installation can fail before any bb command runs, with a message
such as `linked to incompatible ... libruby`. This is a local toolchain problem,
not a restore failure. Do not run a full install to try to repair it.

On a Mac with Homebrew Ruby already installed, the following process-local
wrapper was verified for this workflow. It does not change global gems or the
shell configuration:

```sh
bb_task() {
  env PATH="/opt/homebrew/opt/ruby/bin:$PATH" \
    GEM_HOME=/opt/homebrew/lib/ruby/gems/4.0.0 \
    GEM_PATH=/opt/homebrew/lib/ruby/gems/4.0.0 task "$@"
}
bb_task bb:plan
```

Use the same wrapper for `bb:export`, `check:leaks`, and `bb` if needed. The gem
path above is specific to Homebrew Ruby 4.0; adapt it when the installed Ruby
version changes. Repairing the original Ruby environment is separate from this
configuration backup.

## What is included

The current recipe records:

- Reviewed public plugin sources and their enabled states, including the Gruve
  theme, personal plugins, providers, and the selected bundled plugins.
- Explicitly listed plugin preferences, such as presentation, search limits,
  workflow limits, retry timing, and thread-list layout.
- Approved general preferences, completed-turn display choices, selected
  experiments, the theme ID, and selected sidebar preferences.
- Explicit keyboard overrides under `keyboard`, including platform scopes and
  `disabled` bindings. There are currently no custom overrides to capture.

Marketplaces and plugin sources are always taken from the reviewed recipe,
never discovered from the live machine. A local plugin checkout path therefore
cannot replace a public install source during capture. Already-installed plugins
keep their existing sources when applying the recipe; this lets a development
checkout remain local.

Capture reports the number of unlisted plugins and excluded sidebar entries
without saving their names or values in the recipe. It retains previously saved
values and warns when an approved plugin is disabled or absent. An unexpected
CLI failure, missing approved setting, unknown schema, secret schema field, or
invalid value stops capture instead of pretending the setting is empty.

Changes to free-text plugin settings and the branch prefix are not captured
automatically. Review and edit those values in the recipe deliberately. Number,
boolean, and select plugin settings are checked against their current schemas.
UI provider changes also require review in the recipe before capture accepts
them. Changing to a theme from an unlisted plugin does not publish its identity.

## What stays local

Do not add these to the public recipe:

- Work plugin sources, private marketplaces, internal endpoints, work model
  names, project names, or work-specific instructions.
- Credentials, API keys, authentication headers, browser cookies, account data,
  SSH material, or pairing state. A private Git repo is not a credential store.
- Project, thread, environment, machine, automation, or account IDs.
- Plugin databases and content: PR boards, agent conversations, research,
  prompts, drafts, studies, task memory, saved servers, and schedules.
- Machine access rules, Git credential forwarding, server addresses, ports,
  connection settings, and onboarding state.

Never stow or copy the entire `~/.bb` directory or its `config.json` into `home/`.
The directory mixes preferences with runtime data and credentials. Installed
plugin files are not a backup format either; use the public source recipe.
Custom theme files, custom models, favicon overrides, and bb-specific free-text
instructions are not captured by this workflow. Review these separately before
adding any explicit file-based backup. The current theme comes from its public
plugin, so its generated CSS does not need copying.

Applying the recipe never removes an unlisted plugin or changes its settings.
Panel order, visible panels, footer order, and hidden footer items retain local
entries not named in the recipe. Managed entries are added or ordered without
removing work-only entries. Other declared scalar settings are intentionally
shared across machines. Removing an entry from the desired settings stops applying it;
it does not uninstall a plugin, reset a shortcut, or hide an existing panel.
UI list approvals live separately in `ui_capture_allowlist`, so a panel hidden on
one machine is not forgotten as a permitted entry. Remove it from both places
to stop applying it and revoke permission for future captures.

The installer still supports machine profiles for apply. Capture refuses a
recipe with nonempty `profiles` so a machine-specific override cannot accidentally
be flattened into shared settings. Keep this recipe work-free on every profile.

## Approving an addition

Review the public source and the setting's purpose before adding it to `bb.yml`.
Add a plugin as `id@marketplace`, or as an `id` and an explicit public `source`.
List its setting keys with reviewed values under `plugin_settings`. An installed
plugin is not automatically trusted, even when its schema marks a field nonsecret.
Do not approve fields that hold endpoints, commands, names, prompts, or other
work content just because they are not credentials.

For a sidebar list, add each permitted entry to `ui_capture_allowlist` under the
matching UI key. Capture filters the live list against those entries and writes
the current visibility or ordering into `ui`; it does not learn new entries or
erase approvals when a panel is absent. The first capture seeds approvals from
the existing `ui` arrays when no separate approvals exist. For a keyboard binding,
add a record such as `command: panel.nextTab` with `shortcut: Mod+K` and optionally
`platform: mac`. Capture refreshes the saved overrides of that command. If no
override exists, it warns and keeps the recipe rather than guessing whether you
wanted to reset it. Delete the record to stop managing it.

Supported general and UI keys live in `src/install/bb_snapshot.rb`. Expanding
those lists is a code change that needs privacy review and a test. Unknown
sections and connection-related general keys fail capture.

## Privacy checks and their limits

The checker scans `bb.yml`, all of `bb/`, and the public disk-audit helper.
It flags the known employer name, credential-like fields, email addresses, home
paths, runtime IDs, and common token formats. If the existing private companion
repo is present, it also reads `leak-denylist.txt` from there. That list can hold
additional internal terms and names without publishing the list itself. If it
is absent or empty, capture warns that only generic checks are available.

The pre-commit hook checks staged bytes, not the working copy. Errors redact
values and private denylist patterns. The hook is enabled by `task up`; inspect
it with `git config --get core.hooksPath` (expected: `.githooks`). Checks do not
stage, commit, or push anything.

An allowlist reduces accidental disclosure; pattern checks cannot prove that
arbitrary text contains no private information. Review every diff, especially
when adding sources or settings. These checks are scoped to the bb backup, not
a claim that the entire shell repository or its Git history has been audited.

## Automations and Shuttle remain separate

`task bb:export` and `task bb` never capture or restore automations, or the Shuttle plugin's
servers, presets and free-text settings. Shuttle's backup goes only to the private repo with
`task bb:shuttle:export`; see [the installation guide](installation.md#shuttle). The existing
`bb:automations` commands still use their separate public/private workflow.
Run those only deliberately: restoring an enabled schedule makes it run on that
machine too. See [the installation guide](installation.md#bb-automations).
