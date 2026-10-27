# Installation

## Quick Install

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/kalindudc/shell/main/install.sh)"
```

Only `curl` is needed. The script clones the repository to `~/src/github.com/kalindudc/shell`
(the flake links files from that path, so it must live there) and runs itself from the clone.
In an existing checkout, run `./install.sh` or `task install`. It is safe to run again.

## What install.sh does

1. On macOS, makes sure the Xcode Command Line Tools are installed. On Linux, installs git
   and curl, then runs `src/scripts/linux-system.sh` for what the distribution keeps: zsh as
   the login shell, Docker and its group, pyenv build tools, FUSE, Ghostty, VS Code and the
   flatpak apps.
2. Installs Nix with the Determinate Systems installer, unless Nix is already there (on the
   work Mac, Tec provides it).
3. Stops if the login name differs from `nix/user.nix`.
4. On macOS, installs Homebrew, which nix-darwin needs for the casks.
5. Runs `task switch` (`src/scripts/switch.sh`): removes links left by the old stow layout,
   then applies the flake with nix-darwin on macOS or Home Manager on Linux.
6. Runs `ruby src/install.rb` for what Nix does not manage: `tools`, `setup`, `bb` and
   `cortex` (see below).
7. Lists anything that needs a new login, such as the docker group or the zsh login shell.

## Profiles

On macOS the flake has two configurations:

| Profile | Use | Difference |
|---------|-----|------------|
| `personal` | Any Mac without Tec | Nix installs git, gh and Ruby |
| `work` | The Shopify Mac | Tec supplies Nix, git, gh, Ruby, Node and pnpm, so Nix does not |

`./install.sh work` or `task switch -- work` picks one. Without an argument, `task switch`
reuses the profile of the last switch (`/etc/shell-profile`), else picks `work` when
`~/.local/state/tec` exists, else `personal`.

On Linux the configuration is `linux-x86_64` or `linux-aarch64`, from `uname -m`.

## Commands

```bash
task switch              # apply the flake after changing nix/, the zsh files or the file list
task update              # update flake.lock (nixpkgs, nix-darwin, Home Manager), then task switch
task check               # evaluate every configuration and build this system's checks
task tools               # npm, pi and pipx packages, herdr plugins, the bb AppImage on Linux
task setup               # GPG signing key, pi extension dependencies, SKILL_NOTES.md templates
task bb                  # start bb if needed and apply bb.yml
task cortex              # install cortex and its agent integrations

TRACE=1 ./install.sh            # print every command
SHELL_SKIP_STEPS=1 ./install.sh # apply the flake only
```

## Adding Packages

| What | Where |
|------|-------|
| A command-line tool for every machine | `nix/home/packages.nix` (search [nixpkgs](https://search.nixos.org/packages)) |
| A macOS app | `homebrew.casks` in `nix/darwin/default.nix` |
| A font | `fonts.packages` in `nix/darwin/default.nix` and `home.packages` in `nix/home/linux.nix` |
| A Linux system package or desktop app | `src/scripts/linux-system.sh` |
| An npm, pi or pipx package | `packages.yml` |

Then run `task switch` (or `task tools` for `packages.yml`). Agent CLIs such as pi stay on
npm because nixpkgs lags behind their releases.

Homebrew only installs what is listed and never removes anything
(`homebrew.onActivation.cleanup = "none"`). If an app is already in `/Applications` but was not
installed by Homebrew, `brew bundle` can fail on that cask; delete the app or run
`brew install --cask --adopt <cask>` once, then `task switch` again.

## Environment Configuration

`task setup` reads `SHELL_DIR/.env`:

```bash
GIT_EMAIL=you@example.com
GIT_NAME=Your Name
GIT_SIGNING_KEY=YOUR_GPG_KEY_ID
```

It finds or creates a GPG signing key for `GIT_EMAIL`, uploads it to GitHub when `gh` is
signed in, and writes it to `~/.config/git/signing`, which turns on commit signing.

The git identity itself is in `nix/user.nix`. Home Manager writes the git config to
`~/.config/git/config` (read-only), in this order: the settings, then `~/.config/git/signing`,
then `git/gitconfig` from the private
[kalindudc/shell-private](https://github.com/kalindudc/shell-private) repo at
`~/src/github.com/kalindudc/shell-private`. That last file holds conditional includes, matched by
remote URL or folder, that give work repos the work email and signing key. The rules live there
because they name work systems. Without the private repo, every repo uses the identity above.

Git reads `~/.gitconfig` after `~/.config/git/config`, and `git config --global` writes there,
so tools such as `dev`, `gh auth setup-git` and `git maintenance` keep working. Reading with
`git config --global --get` looks only at `~/.gitconfig`; use `git config --get`, which reads
every file.

If `.env` is missing, the git config values are used as fallbacks.

## bb

The bb app comes from the `bb` cask on macOS (nix-darwin), and on x86_64 Linux from the
official AppImage at `~/Applications/bb.AppImage`, with a desktop entry (`task tools`).
bb updates itself after that.

`bb.yml` declares what bb should have on every machine:

- plugin marketplaces;
- plugins, as `<id>@<marketplace>`, or as an `id` and a git `source` for a plugin that no
  marketplace lists;
- bundled plugins to turn on or off;
- per-plugin settings, Settings → General values, how each provider shows finished turns,
  experiments, sidebar preferences (such as Switchboard as the thread list) and the theme.

bb keeps these in its own database, so they are applied through the bb CLI rather than
linked. Work-only plugins and settings stay out of this public file.

The bb step runs near the end of the install. When bb is not running, the step starts it in
the background and waits up to two minutes for it to answer. It then puts the `bb` command on
PATH (Settings → General → Command line) and applies `bb.yml`. If bb does not start, for
example over SSH without a display, the step is skipped with a warning; open bb, then run:

```bash
task bb
```

The step only adds and changes what `bb.yml` lists; it never removes plugins, marketplaces
or settings. Machine-specific state goes under `profiles:` in `bb.yml`, selected by
`SHELL_MACHINE_PROFILE` (for example `SHELL_MACHINE_PROFILE=work` in `.env`), else `default`.

My own plugins live in [kalindudc/bb-marketplace](https://github.com/kalindudc/bb-marketplace).

### bb automations

bb keeps automations (scheduled agent prompts and scripts) in its database too. They are backed up
as one folder per automation: `automation.yml` with the schedule, provider, model and environment,
plus `prompt.md` or the script. Ids, run history and stored paths are left out, projects are named,
and paths start at `~`, so a folder restores on any machine.

Most automations name work systems or people, so the backup is split across two repos:

- `bb/automations/` in this public repo holds only automations already tracked here. Today that is
  the weekly disk report, whose script is `home/bin/disk-audit`.
- The private [kalindudc/shell-private](https://github.com/kalindudc/shell-private) repo, cloned to
  `~/src/github.com/kalindudc/shell-private` (or `SHELL_PRIVATE_DIR`), holds every other automation,
  copies of the helper folders they call, the work-only overlay for `disk-audit`, and the leak
  check's denylist of work terms and names.

```bash
task bb:automations:export          # save every automation, then review and commit both repos
task bb:automations                 # restore: create missing automations and helper files
task bb:automations -- --update     # also make changed automations match the saved files
task check:leaks                    # scan the public backup for ids, paths, tokens and work terms
```

The export writes a new automation to the private repo, never to this one; making one public means
moving its folder here on purpose. Before it writes a public folder, the export runs the leak check
and refuses on any hit. The same check runs in `task test:unit` and in the pre-commit hook
(`.githooks/pre-commit`, turned on by `task up` with `git config core.hooksPath .githooks`). Without
the private repo it checks only the generic patterns.

Restoring is never automatic: it creates automations that then run on their own, so run it on
purpose and pause the copies on any machine that should not run them. It never deletes an
automation, and it leaves one that differs from its files alone unless you pass `--update`.

## cortex

After the bb step, the installer sets up cortex, a task tracker in the private
`kalindudc/cortex` repository:

1. If `cortex` is not installed, it clones the repository next to this one with `gh` and
   builds it with `pnpm run deploy`, which copies the binary to `~/bin/cortex`. An existing
   checkout is built as it is and never pulled.
2. `cortex init` creates the database when there is none.
3. `cortex agents install` writes cortex's agent skills, its pi extension and, because bb is
   running by then, its bb plugin.

The clone needs `gh auth login` first, and the build needs pnpm (installed from npm by
`task tools`). When either is missing the step is skipped with a warning. To run it again:

```bash
task cortex
```

## After Install

```bash
exec zsh  # Restart shell (or open a new terminal)

# Verify key tools
starship --version
fzf --version
atuin --version
atuin doctor
nvim --version
```

## Atuin history migration

Atuin replaces the legacy oh-my-zsh history aliases (`h`, `hl`, `hs`, `hsi`) and old Ctrl-R history search. fzf still handles non-history workflows such as completion, Ctrl-T, Alt-C, Kubernetes helpers, and todo tooling; native zsh still handles Up/Down prefix search until Atuin changes directory filtering for those keys.

Migration is manual and safe by default: import existing zsh history with `HISTFILE=$HOME/.zsh_history atuin import zsh`, open interactive search with `atuin search -i`, inspect your encryption key with `atuin key`, then opt into sync with `atuin sync` or force reconciliation with `atuin sync -f` when needed. Before pruning imported history, review `atuin history prune --dry-run`.

Only non-secret Atuin client config is tracked in this repo. Atuin secrets and state, including keys, sessions, and `history.db`, stay in Atuin's default data directory under `~/.local/share/atuin` and should not be committed.

## Troubleshooting

**Installation interrupted?** Run `./install.sh` again; every step is safe to repeat.

**Home Manager says a file is in the way?** It moves the old file aside as `<name>.before-nix`
and links its own. If a `.before-nix` copy already exists, delete it after checking its
contents, then run `task switch` again.

**Want to see what's happening?** Run `TRACE=1 ./install.sh`.
