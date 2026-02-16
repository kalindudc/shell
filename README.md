# shell

> Shared and common aliases and functions for all machines with unified cross-platform installation.

## Features

### What do you get?

- [oh-my-zsh](https://github.com/ohmyzsh/ohmyzsh#unattended-install) - ZSH framework
- [starship](https://starship.rs/) - Fast, customizable prompt
- [enhancd](https://github.com/babarot/enhancd) - Fuzzy `cd` with history
- [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions) - Command suggestions based on history
- [zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting) - Syntax highlighting
- [fzf](https://github.com/junegunn/fzf) - Fuzzy finder
- [zoxide](https://github.com/ajeetdsouza/zoxide) - Smarter cd command
- [ripgrep](https://github.com/BurntSushi/ripgrep) - Fast grep alternative
- Development tools: neovim, gh (GitHub CLI), gcc, git-delta
- Runtime managers: pyenv, nvm, go
- DevOps tools: kubectl, helm, docker, docker-compose
- Custom aliases and functions - see `./home/.zshrc`
- Helpful scripts - see `./home/bin/`

## Installation

### Quick Start (All Platforms)

The new unified installation script automatically detects your operating system and installs everything you need.

**Prerequisites**: Only `curl` is required. The script will automatically install `git` if needed.

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/kalindudc/shell/main/install.sh)"
```

This command:
1. Downloads and runs the installation script
2. Automatically clones the repository to `~/src/github.com/kalindudc/shell` (or `$SHELL_INSTALL_DIR/shell` if set)
   - If the directory already exists, it will `git pull` to update instead of re-cloning
3. Re-executes the script from the cloned repository
4. Proceeds with the full installation

**Supported Platforms:**
- macOS (Intel & Apple Silicon) with Homebrew
- Ubuntu/Debian with apt
- Arch Linux with pacman/yay

### Installation Options

**Via one-liner with options:**

```bash
# Skip fonts during one-liner installation
bash -c "$(curl -fsSL https://raw.githubusercontent.com/kalindudc/shell/main/install.sh)" -s --skip-category=fonts

# Non-interactive installation via one-liner
NONINTERACTIVE=1 bash -c "$(curl -fsSL https://raw.githubusercontent.com/kalindudc/shell/main/install.sh)"

# Custom installation directory
SHELL_INSTALL_DIR="$HOME/custom/path" bash -c "$(curl -fsSL https://raw.githubusercontent.com/kalindudc/shell/main/install.sh)"
# This will clone to: $HOME/custom/path/shell
```

**After cloning the repository:**

```sh
# Standard installation (auto-detect OS)
./install.sh

# Skip specific categories
./install.sh --skip-category=fonts
./install.sh --skip-category=optional

# Resume from failed step
./install.sh --continue

# Reset and start fresh
./install.sh --reset-state

# Non-interactive mode
NONINTERACTIVE=1 ./install.sh

# Debug mode
TRACE=1 ./install.sh

# Show current installation state
./install.sh --show-state

# Get help
./install.sh --help
```

### Package Categories

The installation is organized into categories that can be skipped:

- `core` - Essential packages (git, curl, stow, ruby)
- `shell` - Shell tools (zsh, fzf, ripgrep, zoxide)
- `dev` - Development tools (neovim, gh, gcc, git-delta)
- `runtimes` - Runtime managers (pyenv, nvm, go)
- `devops` - DevOps tools (kubectl, helm, docker, docker-compose)
- `fonts` - Nerd Fonts
- `optional` - Optional packages (vscode, ghostty, 1password-cli)

## Architecture

### Modular Design

The installation system is built with modularity and maintainability in mind:

```
install.sh                    # Main orchestration script
├── src/lib/common.sh         # Shared utilities (logging, prompts, version comparison)
├── src/lib/os_detect.sh      # OS/distro/architecture detection
├── src/lib/state.sh          # State management and resume capability
└── src/lib/packages.sh       # Package installation abstraction
```

### State Management

The installer tracks progress in `~/.shell_install_state`, allowing you to:

- **Resume after failures** - Pick up exactly where you left off
- **Skip completed steps** - No re-installation of already completed work
- **Preserve context** - Maintains OS detection and user inputs across runs

### Key Features

- **Auto-detection** - Automatically detects OS, distribution, and architecture
- **Resume capability** - Continue from any failed step with `--continue`
- **Lock file protection** - Prevents concurrent installations
- **Idempotent** - Safe to run multiple times
- **Category-based** - Install only what you need
- **Comprehensive testing** - Unit and integration tests for reliability

## Directory Structure

```
.
├── install.sh                # Unified installation script
├── src/
│   ├── lib/                  # Modular libraries
│   │   ├── common.sh         # Shared utilities
│   │   ├── os_detect.sh      # OS detection
│   │   ├── state.sh          # State management
│   │   └── packages.sh       # Package management
│   ├── templates/            # ERB templates
│   ├── generate_template.rb  # Template generator
│   ├── generate_zshrc.rb     # .zshrc generator
│   └── setup.sh              # Setup script
├── home/                     # Home directory configs (stowed)
│   ├── bin/                  # Useful scripts
│   ├── .zshrc                # Auto-generated
│   └── ...
├── test/
│   ├── unit/                 # BATS unit tests
│   └── integration/          # Docker integration tests
├── docs/
│   └── legacy/               # Deprecated OS-specific scripts
├── Taskfile.yml              # Task runner configuration
└── .shellcheckrc             # ShellCheck configuration
```

## Development

### Prerequisites

```sh
# Install development dependencies
task dev:setup
```

### Running Tests

```sh
# Run all tests
task test

# Run unit tests only
task test:unit

# Run integration tests (requires Docker)
task build                                    # Build Docker images first (one-time)
task test:integration                         # Run all platforms
task test:integration -- ubuntu-22            # Run Ubuntu 22.04 only
task test:integration -- ubuntu-24 debian     # Run specific platforms
task test:integration -- arch                 # Run Arch Linux only

# Or run test script directly
./test/integration/run-install-test.sh                # All platforms
./test/integration/run-install-test.sh ubuntu-22      # Single platform
./test/integration/run-install-test.sh ubuntu-22 arch # Multiple platforms

# Rebuild images from scratch
task build:clean

# Lint and format shell scripts
task style
```

### Available Tasks

```sh
# Core tasks
task install              # Run installation
task stow                 # Re-stow home directory
task clean                # Clean all generated files and state

# Code quality
task style                # Run linting and auto-fix formatting

# Docker image building
task build                # Build integration test images
task build:clean          # Rebuild images from scratch (no cache)

# Testing
task test                 # Run all tests (unit + integration)
task test:unit            # Run unit tests with BATS
task test:integration     # Run integration tests (all platforms)
# Pass platform names after -- to test specific platforms:
# task test:integration -- ubuntu-22
# task test:integration -- ubuntu-24 debian

# Configuration generation
task generate             # Generate .zshrc and .gitconfig
task generate:zsh         # Re-generate .zshrc
task generate:gitconfig   # Re-generate .gitconfig
```

## Troubleshooting

### Installation Issues

```sh
# Enable debug mode
TRACE=1 ./install.sh

# View current state
./install.sh --show-state

# Reset and retry
./install.sh --reset-state

# Continue from last successful step
./install.sh --continue
```

### Common Problems

**Installation hangs or fails:**
- Check `./tmp/shell_install.lock` or `~/.shell_install.lock` for stale locks
- Review `~/.shell_install_state` for completed steps
- Try `./install.sh --reset-state` to start fresh

**Package installation fails:**
- Ensure package manager is up to date
- Check internet connectivity
- Try installing problematic category separately

**State file issues:**
```sh
# Clean all state and lock files
task clean

# Or manually
rm -f ~/.shell_install_state
rm -f ~/.shell_install.lock
rm -f ./tmp/shell_install.lock
```

**Docker permissions on Linux:**
After installing Docker, you may need to log out and back in for group membership to take effect:
```sh
# Check if you're in the docker group
groups | grep docker

# If not, the installation added you but you need to refresh your session
# Either log out/in or run:
newgrp docker

# Test docker access
docker ps
```

## Contributing

### Code Standards

- Use **2-space indentation** for all shell scripts
- Follow [Shell Script Best Practices](https://sharats.me/posts/shell-script-best-practices/)
- All scripts must pass ShellCheck with zero warnings
- Add tests for new functionality
- Update documentation

### Testing Requirements

Before submitting changes:

```sh
# Run linting and formatting
task style

# Build Docker images (first time or after Dockerfile changes)
task build

# Run all tests
task test

# Or run individually
task test:unit
task test:integration

# Test specific platforms only
task test:integration -- ubuntu-24
task test:integration -- debian arch
```

## Migration from Legacy Scripts

The old OS-specific scripts (`install-macos.sh`, `install-linux.sh`, `install-arch.sh`) have been deprecated. See [docs/legacy/README.md](docs/legacy/README.md) for migration instructions.

## Performance

On modern hardware:
- **Apple Silicon Macs** - Shell startup under 400ms
- **Intel Macs (2018+)** - Shell startup under 700ms
- **Linux systems** - Shell startup under 500ms

## License

MIT

## Credits

- PRP commands and templates: https://github.com/Wirasm/PRPs-agentic-eng/
- Homebrew installation patterns: https://github.com/Homebrew/install
- Shell best practices: https://sharats.me/posts/shell-script-best-practices/
