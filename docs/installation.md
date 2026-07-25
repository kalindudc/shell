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
| `pipx` | Python CLI tools | All |
| `custom` | Special installers | All |

## Custom Installers

Packages in `custom_bootstrap:` run before npm/pipx so runtime managers exist first. Packages in the `custom:` section run after shared package backends and call Ruby methods for complex installations:

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

To add a custom installer, add the method name to `custom:` in `packages.yml` and define the method in `src/install/custom.rb`.

## Environment Configuration

The installer reads configuration from `SHELL_DIR/.env`:

```bash
GIT_EMAIL=you@example.com
GIT_NAME=Your Name
GIT_SIGNING_KEY=YOUR_GPG_KEY_ID
```

If `.env` is missing, git config values are used as fallbacks.

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
