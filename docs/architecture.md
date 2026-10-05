# Architecture

## Overview

Unified installer with a minimal bash bootstrap and Ruby orchestrator reading declarative package manifests.

## Components

```
install.sh                    # Bash bootstrap: installs git + ruby, execs Ruby orchestrator without Bundler
src/install.rb                # Ruby entry point: parses CLI, loads stdlib-only installer runtime
src/install/{main,*.rb}       # Orchestrator, OS, backend, state, dependency, and post-setup modules
packages.yml                  # Declarative package-manager, machine-profile, and backend manifest
```

## Installation Flow

1. **Bootstrap** (`install.sh`)
   - If run via curl: clone repo, re-execute from cloned location
   - Ensure git is installed
   - Ensure ruby is installed
   - Exec `ruby src/install.rb` without Bundler

2. **Orchestration** (`src/install.rb`)
   - Detect OS (10 lines: reads `/etc/os-release` or checks `RUBY_PLATFORM`)
   - Reject unsupported OS IDs before shared backends run
   - Ensure required package managers exist first (Homebrew can be installed on macOS)
   - Resolve `machine_profiles` by `SHELL_MACHINE_PROFILE`, hostname, then `default`
   - Run package-manager bootstrap, profile dependencies, system update, backend packages, then post-install
   - Record reboot/login-session requirements in `~/.local/state/shell/install.json`

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
  - "@earendil-works/pi-coding-agent"

custom_bootstrap:
  - install_fnm_curl

custom:
  - install_zsh_plugins
  - install_pyenv
```

Backends are executed in order:
1. Package-manager bootstrap from `package_managers`
2. Machine-profile bootstrap dependencies
3. OS-specific backends (system packages first)
4. `custom_bootstrap` runtime setup
5. Shared backends (`npm`, `pipx`, then `custom`)

## OS Detection

Minimal detection (~10 lines):
- Read `/etc/os-release` `ID=` field for Linux
- Check `RUBY_PLATFORM` for Darwin (macOS)
- Map to backend list via constant hash

No OS-specific package name mapping — package names are declared per-backend in YAML.

## Custom Installers

The `custom_bootstrap:` and `custom:` backends call Ruby methods for packages needing special logic:
- `install_docker_post` — enable docker service, add user to docker group
- `install_pyenv` — curl installer
- `install_zsh_plugins` — git clone plugin repos
- `install_fzf_latest` — GitHub releases download
- `install_delta_deb` — GitHub .deb download
- `install_zoxide_curl` — curl installer
- `install_starship_curl` — curl installer
- `install_fnm_curl` — curl installer used before npm
- `install_nerd_fonts_brew` — brew search + install
- `install_nvm_curl` — curl installer (fallback)

## Configuration Generation

ERB template generation unchanged:
- `generate_zshrc.rb` — generates `.zshrc`
- `generate_tempate.rb` — generates `.gitconfig` from template

## Dotfile Symlinking

`home/` is a stow package linked into `$HOME`:
```
stow home -d $SHELL_DIR -t $HOME --adopt
```

Run it through `./install.sh --stow` or `task stow`, not by hand, because of the step below.

### Directories that stay real

When a directory does not exist in `$HOME` yet, stow "folds" it: it replaces the whole directory with one symlink into the repo. Every file a tool later writes there (installed skills, pi sessions, credentials) then lands in the repo and has to be gitignored.

To prevent this, a directory in `home/` that contains an empty `.stow-unfold` marker is created as a real directory in `$HOME` before stow runs (`src/install/unfold.rb`). Stow then links each tracked child individually, and anything a tool adds next to them stays out of the repo. The markers themselves are excluded in `home/.stow-local-ignore`.

Current markers: `.pi`, `.pi/agent`, `.pi/agent/extensions`, `.agents`, `.agents/skills`, `.config`, `.config/herdr`, `.gnupg`, `bin`.

Add a marker when tools write into a directory that also holds tracked files. The tradeoff: a new top-level item in a marked directory (for example a new skill under `home/.agents/skills/`) needs `task stow` before it shows up in `$HOME`. New files inside an existing skill or extension appear immediately, because those directories are still single links.

The stow step refuses to run when a marked directory is still a folded symlink. Convert an existing machine once with the migration script. It moves gitignored runtime files out of the repo into the real directories, so close every pi and Claude session first:
```
ruby src/scripts/unfold-home.rb            # dry run: print the plan
ruby src/scripts/unfold-home.rb --apply    # migrate; writes ~/.local/state/shell/unfold-manifest.json
ruby src/scripts/unfold-home.rb --revert   # undo using that manifest
```

## Sudo Handling

Sudo is requested once at startup and kept alive via background process:
- `sudo -v` to prompt
- Background loop: `while true; do sudo -n true; sleep 50; done`
- `at_exit` kills the background process

## State Management

Minimal continuation state is stored at `~/.local/state/shell/install.json` (or `$XDG_STATE_HOME/shell/install.json`). It records completed phases and reboot/login-session reasons. When a task such as Docker group membership or default shell change requires a new session, the installer saves the reason, prints it, exits 0, and expects a later `./install.sh` run to continue. There are no lock files and no `--continue`, `--reset-state`, or `--show-state` flags.

## Supported Platforms

| OS | Backends |
|----|----------|
| Arch Linux | pacman, yay, flatpak, custom_bootstrap, npm, pipx, custom |
| Ubuntu | apt, snap, flatpak, custom_bootstrap, npm, pipx, custom |
| Debian | apt, flatpak, custom_bootstrap, npm, pipx, custom |
| macOS | brew, brew_cask, custom_bootstrap, npm, pipx, custom |
