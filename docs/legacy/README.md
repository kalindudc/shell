# Legacy Installation Scripts

## Deprecation Notice

The OS-specific installation scripts in this directory have been **deprecated** and replaced with a unified `install.sh` script in the root directory.

## Why the Change?

The previous installation approach had several issues:

- **70% code duplication** across three OS-specific scripts
- **No state tracking** - installations would restart from the beginning on failure
- **No concurrent execution protection** - no lock file mechanism
- **Hardcoded package lists** - difficult to maintain and extend
- **No resume capability** - couldn't continue from where you left off

## New Unified Approach

The new `install.sh` script provides:

- **Single installation script** that auto-detects your operating system
- **State management** - resume from any failed step
- **Modular libraries** - reusable code in `src/lib/`
- **Category-based packages** - skip categories you don't need
- **Lock file protection** - prevents concurrent installations
- **Comprehensive testing** - unit and integration tests

## Migration Guide

### Old Way (Deprecated)

```bash
# macOS
./install.sh

# Ubuntu/Debian
./install-linux.sh

# Arch Linux
./install-arch.sh
```

### New Way

```bash
# All platforms - auto-detects OS
./install.sh

# Skip categories
./install.sh --skip-category=fonts

# Resume after failure
./install.sh --continue

# Reset and start fresh
./install.sh --reset-state

# Non-interactive mode
NONINTERACTIVE=1 ./install.sh

# Debug mode
TRACE=1 ./install.sh
```

## Legacy Scripts

These scripts are preserved for reference only:

- `install-macos.sh` - macOS installation with Homebrew
- `install-linux.sh` - Ubuntu/Debian installation with apt
- `install-arch.sh` - Arch Linux installation with pacman/yay

**Do not use these scripts.** They are no longer maintained and may not work correctly.

## Getting Help

For the new installation system:

```bash
./install.sh --help
```

For issues or questions, please refer to the main [README.md](../../README.md) in the root directory.
