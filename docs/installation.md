# Installation

## Quick Install

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/kalindudc/shell/main/install.sh)"
```

Requires: `curl` for the one-line download path. Once the repository is available, `install.sh` installs Homebrew on macOS, then any missing `git` and Ruby, and runs `ruby src/install.rb` without Bundler.

## Architecture

The installer uses a two-stage design:

1. **Bash Bootstrap** (`install.sh`)
   - If run via curl: clones the repo, re-executes from the clone
   - macOS: loads Homebrew, or installs it when it is missing
   - Installs missing git; on macOS switches to Homebrew's Ruby when the Ruby on PATH is older than 3.1, and on Linux installs the distribution's Ruby when it is missing
   - Fails with the exact manual next step when sudo or a package manager is unavailable
   - Hands off with `ruby src/install.rb` (no Bundler at installer runtime)

2. **Ruby Installer** (`src/install.rb`) runs these steps in order, or only the ones you name:

   | Step | What it does |
   |------|--------------|
   | `packages` | Updates system packages, then installs the `packages.yml` lists for this platform, plus npm, pi and pipx packages |
   | `tools` | Installs tools no package manager provides (zsh plugins, starship, herdr, the bb app on Linux, ...) |
   | `setup` | Sets up docker, the GPG signing key, herdr plugins, pi extension dependencies, skill notes and zsh as the login shell |
   | `generate` | Writes `home/.zshrc` with zsh completions, `home/.gitconfig` and the ghostty font-size config |
   | `stow` | Links `home/` into `$HOME` |
   | `bb` | Starts bb if needed and applies `bb.yml` |
   | `cortex` | Installs cortex, then its agent skills, pi extension and bb plugin |

Supported platforms: macOS, Arch Linux and its derivatives, and Ubuntu, Debian and their derivatives.

## Commands

```bash
task install                  # everything, in the order above
task install:packages         # one step: also install:tools, install:setup, install:bb, install:cortex
task generate                 # zsh, git and ghostty configs
task generate:zsh             # one config: also generate:git, generate:ghostty
task stow                     # link home/ into $HOME

# The same through install.sh, which takes any number of steps
./install.sh [--trace] [STEP...]
./install.sh generate zsh ghostty
./install.sh --help

# Non-interactive
NONINTERACTIVE=1 ./install.sh
```

## Adding Packages

Edit `packages.yml` and add a line under the appropriate backend:

```yaml
pacman:
  - existing-package
  - your-new-package    # <-- add here for Arch

apt:
  - existing-package
  - your-new-package    # <-- add here for Ubuntu/Debian

brew:
  - existing-package
  - your-new-package    # <-- add here for macOS
```

Backends are organized by package manager, not by OS:

| Backend | Description | Platforms |
|---------|-------------|-----------|
| `pacman` | System packages | Arch |
| `yay` | AUR packages | Arch |
| `apt` | System packages | Ubuntu, Debian |
| `snap` | Snap packages | Ubuntu, Debian |
| `flatpak` | Flatpak apps | Linux |
| `brew` | Homebrew formulas | macOS |
| `brew_cask` | Homebrew casks | macOS |
| `npm` | Global npm packages | All |
| `pi` | pi packages, added with `pi install` (skips ones `pi list` already shows) | All |
| `pipx` | Python CLI tools | All |

`brew`, `pacman` and `apt` must exist. Any other backend is skipped with a warning when its command is missing, so on Arch list a package under `yay` only when the official repositories lack it.

## Tools

`src/install/tools.rb` installs what no package list provides. `Tools::ALL` lists the installers in the order they run, and each one returns early when its tool is already installed:

- `install_pyenv` — install pyenv via curl
- `install_gum` — install charmbracelet/gum via go, where no package provides it
- `install_zsh_plugins` — clone zsh plugins used by the generated config
- `install_fzf_latest` — download latest fzf from GitHub
- `install_atuin` — install Atuin history search/sync via the official installer fallback
- `install_delta_deb` — download git-delta .deb for Ubuntu and Debian
- `install_zoxide_curl` — install zoxide via curl
- `install_starship_curl` — install starship via curl
- `install_herdr` — install herdr via curl
- `install_bb_appimage` — install the bb AppImage on x86_64 Linux

To add a tool, define the method in `src/install/tools.rb` and add its name to `Tools::ALL`. Setup that needs an installed tool (herdr plugins, the herdr pi integration, docker group) goes in `src/install/setup.rb`.

## Environment Configuration

The installer reads configuration from `SHELL_DIR/.env`:

```bash
GIT_EMAIL=you@example.com
GIT_NAME=Your Name
GIT_SIGNING_KEY=YOUR_GPG_KEY_ID
```

A variable already set in the environment wins over `.env`. When `GIT_*` is missing, git's global `user.name`, `user.email` and `user.signingkey` are used.

## bb

The installer adds the bb app: the `bb` cask on macOS, and on x86_64 Linux the official
AppImage at `~/Applications/bb.AppImage`, with FUSE 2 and a desktop entry. bb updates
itself after that.

`bb.yml` declares what bb should have on every machine:

- plugin marketplaces;
- plugins, as `<id>@<marketplace>`, or as an `id` and a git `source` for a plugin that no
  marketplace lists;
- bundled plugins to turn on or off;
- per-plugin settings, Settings → General values, how each provider shows finished turns,
  experiments, sidebar preferences (such as Switchboard as the thread list) and the theme.

bb keeps these in its own database, so they are applied through the bb CLI rather than
stowed. Work-only plugins and settings stay out of this public file.

The bb step runs near the end of the install. When bb is not running, the step starts it in
the background and waits up to two minutes for it to answer. It then puts the `bb` command on
PATH (Settings → General → Command line) and applies `bb.yml`. If bb does not start, for
example over SSH without a display, the step is skipped with a warning; open bb, then run:

```bash
task install:bb
```

The step only adds and changes what `bb.yml` lists; it never removes plugins, marketplaces
or settings. Machine-specific state goes under `profiles:` in `bb.yml`, selected by
`SHELL_MACHINE_PROFILE` from the environment or `.env` (for example `SHELL_MACHINE_PROFILE=work`),
otherwise `default`.

My own plugins live in [kalindudc/bb-marketplace](https://github.com/kalindudc/bb-marketplace).

## cortex

After the bb step, the installer sets up cortex, a task tracker in the private
`kalindudc/cortex` repository:

1. If `cortex` is not installed, it clones the repository next to this one with `gh` and
   builds it with `pnpm run deploy`, which copies the binary to `~/bin/cortex`. An existing
   checkout is built as it is and never pulled.
2. `cortex init` creates the database when there is none.
3. `cortex agents install` writes cortex's agent skills, its pi extension and, because bb is
   running by then, its bb plugin.

The clone needs `gh auth login` first, and the build needs pnpm (installed by the `npm`
backend). When either is missing the step is skipped with a warning. To run it again:

```bash
task install:cortex
```

## After Install

```bash
exec zsh  # Restart shell

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

**Installation interrupted?** Just re-run `task install` — every step is safe to run again.

**New login needed?** Joining the docker group and switching the login shell to zsh only take effect in a new login session. The install still runs every step, then lists what needs you to log out and back in.

**Need to skip slow backends?** Set `SKIP_BACKENDS`:
```bash
SKIP_BACKENDS=snap,npm ./install.sh
```

**Want to see what's happening?** Use `./install.sh --trace` for verbose output.
