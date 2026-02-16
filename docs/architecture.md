# Architecture

## Overview

Unified installer with modular libraries, state management, and cross-platform support.

## Components

```
install.sh          # Main entry point
src/lib/
  common.sh         # Logging, prompts, version comparison
  os_detect.sh      # OS/distro/architecture detection
  state.sh          # State tracking and resume capability
  packages.sh       # Package installation
src/setup.sh        # Dotfiles setup (stow, oh-my-zsh, git config)
```

## Installation Steps

1. OS detection
2. Package manager setup
3. Core packages
4. Shell packages
5. Dev packages
6. Runtimes
7. DevOps tools
8. Fonts
9. Optional packages
10. pipx packages
11. Clone repo
12. Run setup
13. Set default shell

Each step is tracked in `~/.shell_install_state` for resume capability.

## State File

`~/.shell_install_state` tracks:
- Completed steps (marked `done`)
- Context: OS_TYPE, OS_DISTRO, OS_ARCH, PACKAGE_MANAGER, GIT_EMAIL, GIT_NAME

## Supported Platforms

- macOS (Homebrew)
- Ubuntu/Debian (apt)
- Arch Linux (pacman/yay)

## Lock Files

- `./tmp/shell_install.lock` (local)
- `~/.shell_install.lock` (bootstrap)

Prevents concurrent installations.
