# Architecture

## Overview

One entry point, `install.sh`, runs a small Ruby installer that works through seven steps. Each step lives in one file under `src/install/`, and the Taskfile only maps task names onto `./install.sh <step>`.

## Components

```
install.sh                    # Bash bootstrap: Homebrew on macOS, git and a Ruby that can run src/install, then src/install.rb
src/install.rb                # Parses the step names, then runs them (stdlib only, no Bundler)
src/install/cli.rb            # Step names, generate targets and --help
src/install/main.rb           # Runner: .env, sudo keepalive, the steps in order, login notices at the end
src/install/platform.rb       # macos, arch or debian, and each platform's package backends
src/install/packages.rb       # Step packages: the packages.yml lists
src/install/tools.rb          # Step tools: installers for what no package list has
src/install/setup.rb          # Step setup: docker, GPG signing key, herdr plugins, pi extensions, skill notes, default shell
src/install/generate.rb       # Step generate: home/.zshrc, home/.gitconfig, ghostty font size
src/install/stow.rb           # Step stow: links home/ into $HOME (with unfold.rb)
src/install/bb.rb, bb_app.rb  # Step bb: starts bb and applies bb.yml with the bb CLI
src/install/cortex.rb         # Step cortex: builds cortex and runs `cortex agents install`
packages.yml                  # Package lists, one per package manager
bb.yml                        # Desired bb state (marketplaces, plugins, plugin and app settings)
```

## Commands

| Task | Runs |
|------|------|
| `task install` | `./install.sh`: every step in order |
| `task install:packages`, `install:tools`, `install:setup`, `install:bb`, `install:cortex` | `./install.sh <step>` |
| `task generate` | `./install.sh generate`: zsh, git and ghostty |
| `task generate:zsh`, `generate:git`, `generate:ghostty` | `./install.sh generate <target>` |
| `task stow` | `./install.sh stow` |

`./install.sh` takes any number of step names and always runs them in the order below, so `./install.sh bb stow` stows first. Every task goes through `install.sh`, even `generate`, because macOS ships Ruby 2.6 and the installer needs a newer one.

## Installation Flow

1. **Bootstrap** (`install.sh`)
   - If run through curl: clone the repo, then re-run from the clone
   - macOS: load Homebrew, or install it when it is missing
   - Install git when it is missing
   - Ruby: on macOS, switch to Homebrew's Ruby only when the Ruby on PATH is older than 3.1; on Linux, install the distribution's Ruby when it is missing
   - Run `ruby src/install.rb` with the given arguments

2. **Steps** (`src/install/main.rb`), in this order:
   1. `packages`: update the system packages, then install the lists for this platform
   2. `tools`: run the installers in `Tools::ALL`; they need curl, git and go from packages
   3. `setup`: docker service and group, `task` symlink for go-task, GPG signing key, herdr plugins and its pi integration, pi extension dependencies, skill notes, zsh as the login shell
   4. `generate`: write the generated configs into `home/`; after setup, so `.gitconfig` gets the signing key setup found, and after tools, so lines installers append to `~/.zshrc` are overwritten
   5. `stow`: link `home/` into `$HOME`
   6. `bb`: start bb when it is not running, then apply `bb.yml`
   7. `cortex`: install cortex, then `cortex agents install`; after bb, so it finds bb running and installs its bb plugin

The Runner loads `SHELL_DIR/.env` once before the first step. A variable already set in the environment wins over `.env`. The sudo keepalive starts only when packages, tools or setup runs.

In a full install, a failing bb or cortex step prints a warning and the install goes on, because bb may not start (for example over SSH) and cortex needs `gh auth login`. Run on its own, the same failure fails the command.

## Package Manifest (`packages.yml`)

Package lists are keyed by package manager, not by OS, and hold nothing else:

```yaml
pacman:
  - git
  - neovim

brew:
  - git
  - neovim

npm:
  - "@earendil-works/pi-coding-agent"

pi:
  - https://github.com/kalindudc/minions
```

`brew`, `pacman` and `apt` are required: when the command is missing, the install fails. Every other backend prints a warning and is skipped when its command is missing, so list in `yay` only what the Arch repositories lack. npm gets Node through fnm first: brew and pacman install fnm, and on Debian or Ubuntu the fnm install script runs (it needs `unzip`). `pi` comes after `npm` because npm installs the pi CLI.

`SKIP_BACKENDS=snap,npm` skips backends by name; the integration tests use it.

## Platforms

`/etc/os-release` decides the platform: `arch` when `ID` or `ID_LIKE` names arch, `debian` when they name debian or ubuntu. Darwin is `macos`. Anything else is unsupported.

| Platform | Backends |
|----------|----------|
| macOS | brew, brew_cask, npm, pi, pipx |
| Arch and derivatives | pacman, yay, flatpak, npm, pi, pipx |
| Ubuntu, Debian and derivatives | apt, snap, flatpak, npm, pi, pipx |

## Tools

`Tools::ALL` in `src/install/tools.rb` lists, in order, the installers for tools that no package list provides: pyenv, gum (through go, when the platform has no package), zsh plugins, a recent fzf, Atuin, git-delta on Debian, zoxide, starship, herdr and the bb AppImage on x86_64 Linux. Each one returns early when its command already exists. To add one, write the method and add its name to `ALL`.

## Configuration Generation

`src/install/generate.rb` renders the ERB templates in `src/templates/`:
- zsh: `.zshrc.erb` with the `*.sh.erb` parts, written to `home/.zshrc`, plus zsh completions for `todo` and `task`
- git: `.gitconfig.erb`, written to `home/.gitconfig` with `GIT_NAME`, `GIT_EMAIL` and `GIT_SIGNING_KEY`
- ghostty: `home/.config/ghostty/config-os` with the font size for this OS

Generating never creates GPG keys or talks to GitHub; `setup` does that. Stow links the generated files into `$HOME`.

## Dotfile Symlinking

`home/` is a stow package linked into `$HOME`:
```
stow home -d $SHELL_DIR -t $HOME --adopt
```

Run it through `task stow`, not by hand, because of the step below.

### Directories that stay real

When a directory does not exist in `$HOME` yet, stow "folds" it: it replaces the whole directory with one symlink into the repo. Every file a tool later writes there (installed skills, pi sessions, credentials) then lands in the repo and has to be gitignored.

To prevent this, a directory in `home/` that contains an empty `.stow-unfold` marker is created as a real directory in `$HOME` before stow runs (`src/install/unfold.rb`). Stow then links each tracked child individually, and anything a tool adds next to them stays out of the repo. The markers themselves are excluded in `home/.stow-local-ignore`.

Current markers: `.pi`, `.pi/agent`, `.pi/agent/extensions`, `.agents`, `.agents/skills`, `.config`, `.config/herdr`, `.gnupg`, `bin`.

Add a marker when tools write into a directory that also holds tracked files. The tradeoff: a new top-level item in a marked directory (for example a new skill under `home/.agents/skills/`) needs `task stow` before it shows up in `$HOME`. New files inside an existing skill or extension appear immediately, because those directories are still single links.

The stow step refuses to run when a marked directory is still a folded symlink. Convert an existing machine once with the migration script. It moves gitignored runtime files out of the repo into the real directories, so close every pi session first:
```
ruby src/scripts/unfold-home.rb            # dry run: print the plan
ruby src/scripts/unfold-home.rb --apply    # migrate; writes ~/.local/state/shell/unfold-manifest.json
ruby src/scripts/unfold-home.rb --revert   # undo using that manifest
```

## Sudo Handling

When packages, tools or setup runs, sudo is requested once at the start and kept alive by a background process:
- `sudo -v` to prompt
- Background loop: `while true; do sudo -n true; sleep 50; done`
- The Runner kills the loop when it finishes

## New Login Sessions

Joining the docker group and switching the login shell to zsh only take effect in a new login session. The install does not stop for them: every step runs, and the install ends with a list of what needs you to log out and back in. Nothing is saved between runs. The docker group is checked first, so a rerun after logging in does not ask again.
