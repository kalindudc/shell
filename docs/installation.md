# Installation

## Quick Install

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/kalindudc/shell/main/install.sh)"
```

Requires: `curl` for the one-line download path. Once the repository is available, `install.sh` bootstraps missing `git` and `ruby` using `apt-get`, `pacman`, or Homebrew, then runs `ruby src/install.rb` without Bundler.

## Architecture

The installer uses a two-stage design:

1. **Bash Bootstrap** (`install.sh`)
   - If run via curl: clones repo, re-executes from clone
   - Installs missing git/ruby with the detected platform package manager
   - Fails with the exact manual next step when sudo or a package manager is unavailable
   - Hands off with `ruby src/install.rb` (no Bundler at installer runtime)

2. **Ruby Orchestrator** (`src/install.rb`)
   - Detects only supported OSes (Arch, Ubuntu, Debian, macOS)
   - Bootstraps required package managers first, including Homebrew on macOS when `brew` is missing
   - Applies the selected `machine_profiles` bootstrap dependencies from `packages.yml`
   - Installs packages via detected backends with required/optional command semantics
   - Generates configs, stows dotfiles, sets up shell, and records reboot/login-session continuation state

## Options

```bash
# Verbose output
./install.sh --trace

# Run stow only (skip package installation)
./install.sh --stow

# Start bb if needed and apply bb.yml only (same as `task bb`)
ruby src/install.rb --bb

# Restore or save bb automations (same as `task bb:automations` and `task bb:automations:export`)
ruby src/install.rb --bb-automations [--update]
ruby src/install.rb --bb-automations-export

# Install cortex and its agent integrations only (same as `task cortex`)
ruby src/install.rb --cortex

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
| `snap` | Snap packages | Ubuntu |
| `flatpak` | Flatpak apps | Linux |
| `brew` | Homebrew formulas | macOS |
| `brew_cask` | Homebrew casks | macOS |
| `custom_bootstrap` | Runtime bootstrap installers such as fnm | All |
| `npm` | Global npm packages | All |
| `pi` | pi packages, added with `pi install` (skips ones `pi list` already shows) | All |
| `pipx` | Python CLI tools | All |
| `custom` | Special installers | All |

## Custom Installers

Packages in `custom_bootstrap:` run before npm, pi and pipx so runtime managers exist first. Packages in the `custom:` section run after shared package backends and call Ruby methods for complex installations:

- `install_docker_post` — enable docker service, add user to docker group
- `install_pyenv` — install pyenv via curl
- `install_gum` — install charmbracelet/gum via go
- `install_zsh_plugins` — clone zsh plugins used by the generated config
- `install_fzf_latest` — download latest fzf from GitHub
- `install_atuin` — install Atuin history search/sync via the official installer fallback
- `install_delta_deb` — download git-delta .deb for Ubuntu
- `install_zoxide_curl` — install zoxide via curl
- `install_starship_curl` — install starship via curl
- `install_fnm_curl` — install fnm via curl (listed in `custom_bootstrap`)
- `install_nerd_fonts_brew` — install all nerd fonts via brew
- `install_nvm_curl` — install nvm via curl (fallback)
- `install_herdr_pi_integration` — install herdr's pi integration, which reports agent state to the herdr sidebar; reinstalled when outdated

To add a custom installer, add the method name to `custom:` in `packages.yml` and define the method in `src/install/custom.rb`.

## Environment Configuration

The installer reads configuration from `SHELL_DIR/.env`:

```bash
GIT_EMAIL=you@example.com
GIT_NAME=Your Name
GIT_SIGNING_KEY=YOUR_GPG_KEY_ID
```

Every repo uses this identity, except the ones that the private
[kalindudc/shell-private](https://github.com/kalindudc/shell-private) repo switches. The
generated `.gitconfig` ends by including `git/gitconfig` from that repo (or from
`SHELL_PRIVATE_DIR`). That file holds conditional includes, matched by remote URL or folder,
that give work repos the work email and signing key. The rules live there because they name
work systems. Without the private repo, every repo uses the identity above.

If `.env` is missing, git config values are used as fallbacks.

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
task bb
```

The step only adds and changes what `bb.yml` lists; it never removes plugins, marketplaces
or settings. Machine-specific state goes under `profiles:` in `bb.yml`, selected like
`machine_profiles`: `SHELL_MACHINE_PROFILE` (for example `SHELL_MACHINE_PROFILE=work` in
`.env`), then a hostname listed under `machine_profiles` in `packages.yml`, then `default`.

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

The clone needs `gh auth login` first, and the build needs pnpm (installed by the `npm`
backend). When either is missing the step is skipped with a warning. To run it again:

```bash
task cortex
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

**Installation interrupted?** Just re-run `./install.sh` — phases are designed to be idempotent.

**Reboot or new login required?** The installer records reasons in `~/.local/state/shell/install.json`, exits 0, and asks you to reboot or log out/in. Run `./install.sh` again after that; the marker is cleared after post-setup continues successfully.

**Need to skip slow backends?** Set `SKIP_BACKENDS`:
```bash
SKIP_BACKENDS=snap,npm ./install.sh
```

**Want to see what's happening?** Use `--trace` for verbose output.
