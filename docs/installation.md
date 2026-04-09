# Installation

## Quick Install

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/kalindudc/shell/main/install.sh)"
```

Requires: `curl` (git and ruby are auto-installed if missing)

## Architecture

The installer uses a two-stage design:

1. **Bash Bootstrap** (`install.sh` ~60 lines)
   - If run via curl: clones repo, re-executes from clone
   - Installs git if missing
   - Installs ruby if missing
   - Hands off to Ruby orchestrator

2. **Ruby Orchestrator** (`src/install.rb` ~300 lines)
   - Detects OS (Arch, Ubuntu, Debian, macOS)
   - Reads `packages.yml` for package list
   - Installs packages via detected backends
   - Generates configs, stows dotfiles, sets up shell

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
| `npm` | Global npm packages | All |
| `pipx` | Python CLI tools | All |
| `custom` | Special installers | All |

## Custom Installers

Packages in the `custom:` section call Ruby methods for complex installations:

- `install_docker_post` — enable docker service, add user to docker group
- `install_pyenv` — install pyenv via curl
- `install_gum` — install charmbracelet/gum via go
- `install_zsh_plugins` — clone oh-my-zsh plugins
- `install_fzf_latest` — download latest fzf from GitHub
- `install_delta_deb` — download git-delta .deb for Ubuntu
- `install_zoxide_curl` — install zoxide via curl
- `install_starship_curl` — install starship via curl
- `install_fnm_curl` — install fnm via curl
- `install_nerd_fonts_brew` — install all nerd fonts via brew
- `install_nvm_curl` — install nvm via curl (fallback)

To add a custom installer, add the method name to `custom:` in `packages.yml` and define the method in `src/install.rb`.

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
nvim --version
```

## Troubleshooting

**Installation interrupted?** Just re-run `./install.sh` — it's idempotent.

**Need to skip slow backends?** Set `SKIP_BACKENDS`:
```bash
SKIP_BACKENDS=snap,npm ./install.sh
```

**Want to see what's happening?** Use `--trace` for verbose output.
