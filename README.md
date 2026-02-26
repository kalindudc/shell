# shell

> Unified cross-platform shell configuration with automated installation for macOS, Ubuntu/Debian, and Arch Linux.

## Features

A comprehensive shell environment with:

- **Shell framework**: [oh-my-zsh](https://github.com/ohmyzsh/ohmyzsh) with [starship](https://starship.rs/) prompt
- **Enhanced navigation**: [enhancd](https://github.com/babarot/enhancd), [zoxide](https://github.com/ajeetdsouza/zoxide), [fzf](https://github.com/junegunn/fzf)
- **Shell improvements**: [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions), [zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting)
- **Development tools**: neovim, gh (GitHub CLI), gcc, git-delta, [ripgrep](https://github.com/BurntSushi/ripgrep)
- **Runtime managers**: pyenv, nvm, go
- **DevOps tools**: kubectl, helm, docker, docker-compose
- **Custom utilities**: Aliases, functions, and scripts tailored for productivity

See [`home/.zshrc`](home/.zshrc) for aliases and [`home/bin/`](home/bin/) for scripts.

## Quick Start

**Prerequisites**: Only `curl` required. The script auto-installs `git` if needed.

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/kalindudc/shell/main/install.sh)"
```

This automatically:
1. Downloads the installation script
2. Clones the repository to `~/src/github.com/kalindudc/shell`
3. Installs and configures your shell environment

**Supported platforms**: macOS (Intel & Apple Silicon), Ubuntu/Debian, Arch Linux

For detailed installation options, see **[Installation Guide](docs/installation.md)**.

## Performance

Shell startup times on modern hardware:
- **Apple Silicon Macs** - Under 400ms
- **Intel Macs (2018+)** - Under 700ms
- **Linux systems** - Under 200ms

## Documentation

- **[Installation Guide](docs/installation.md)** - Installation options, package categories, and customization
- **[Architecture](docs/architecture.md)** - System design, state management, and directory structure
- **[Development](docs/development.md)** - Development setup, testing, and available tasks
- **[Contributing](docs/contributing.md)** - Code standards and testing requirements
- **[Troubleshooting](docs/troubleshooting.md)** - Common issues and solutions

## License

MIT

## Credits

- Homebrew installation patterns: https://github.com/Homebrew/install
- Shell best practices: https://sharats.me/posts/shell-script-best-practices/
