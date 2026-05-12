# Architecture

## Overview

Unified installer with a minimal bash bootstrap and Ruby orchestrator reading declarative package manifests.

## Components

```
install.sh          # Bash bootstrap (~60 lines): installs git + ruby, execs Ruby orchestrator
src/install.rb      # Ruby orchestrator (~300 lines): reads YAML, detects OS, installs packages
packages.yml        # Single declarative package manifest keyed by package manager backend
```

## Installation Flow

1. **Bootstrap** (`install.sh`)
   - If run via curl: clone repo, re-execute from cloned location
   - Ensure git is installed
   - Ensure ruby is installed
   - Exec `src/install.rb`

2. **Orchestration** (`src/install.rb`)
   - Detect OS (10 lines: reads `/etc/os-release` or checks `RUBY_PLATFORM`)
   - Map OS to backends (arch→pacman+yay, ubuntu→apt+snap, macos→brew+brew_cask)
   - Run system update once
   - For each backend: install packages from `packages.yml`
   - Run post-install: config generation, stow, GPG setup, shell change

## Package Manifest (`packages.yml`)

Keyed by package manager backend, NOT by OS:

```yaml
pacman:
  - git
  - curl
  - neovim

yay:
  - github-cli
  - visual-studio-code-bin

brew:
  - git
  - neovim

npm:
  - "@mariozechner/pi-coding-agent"

custom:
  - install_zsh_plugins
  - install_pyenv
```

Backends are executed in order:
1. OS-specific backends (system packages first)
2. Shared backends (npm, pipx, custom)

## OS Detection

Minimal detection (~10 lines):
- Read `/etc/os-release` `ID=` field for Linux
- Check `RUBY_PLATFORM` for Darwin (macOS)
- Map to backend list via constant hash

No OS-specific package name mapping — package names are declared per-backend in YAML.

## Custom Installers

The `custom:` backend calls Ruby methods for packages needing special logic:
- `install_docker_post` — enable docker service, add user to docker group
- `install_pyenv` — curl installer
- `install_zsh_plugins` — git clone plugin repos
- `install_fzf_latest` — GitHub releases download
- `install_delta_deb` — GitHub .deb download
- `install_zoxide_curl` — curl installer
- `install_starship_curl` — curl installer
- `install_fnm_curl` — curl installer
- `install_nerd_fonts_brew` — brew search + install
- `install_nvm_curl` — curl installer (fallback)

## Configuration Generation

ERB template generation unchanged:
- `generate_zshrc.rb` — generates `.zshrc`
- `generate_tempate.rb` — generates `.gitconfig` from template

## Dotfile Symlinking

Stow unchanged:
```
stow home -d $SHELL_DIR -t $HOME --adopt
```

## Sudo Handling

Sudo is requested once at startup and kept alive via background process:
- `sudo -v` to prompt
- Background loop: `while true; do sudo -n true; sleep 50; done`
- `at_exit` kills the background process

## No State Management

- No step tracking file
- No resume capability (just re-run the installer, it's idempotent)
- No lock files
- No `--continue`, `--reset-state`, `--show-state` flags

## Supported Platforms

| OS | Backends |
|----|----------|
| Arch Linux | pacman, yay, flatpak, npm, pipx, custom |
| Ubuntu | apt, snap, flatpak, npm, pipx, custom |
| Debian | apt, flatpak, npm, pipx, custom |
| macOS | brew, brew_cask, npm, pipx, custom |
