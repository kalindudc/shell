# shell

> Shell configuration and packages for macOS, Ubuntu/Debian and Arch Linux, declared in a Nix flake: nix-darwin and Home Manager on macOS, Home Manager on Linux.

## Features

A comprehensive shell environment with:

- **Shell prompt/plugins**: Direct zsh plugin sourcing with [starship](https://starship.rs/) prompt
- **Enhanced navigation**: [zoxide](https://github.com/ajeetdsouza/zoxide) directory jumping plus [fzf](https://github.com/junegunn/fzf) completion, file, and command pickers
- **Shell history**: [Atuin](https://atuin.sh/) history search/sync owns Ctrl-R, while native zsh Up/Down prefix search remains available
- **Shell improvements**: [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions), [fast-syntax-highlighting](https://github.com/zdharma-continuum/fast-syntax-highlighting)
- **Development tools**: neovim, gh (GitHub CLI), gcc, git-delta, [ripgrep](https://github.com/BurntSushi/ripgrep)
- **Runtime managers**: pyenv, fnm, go
- **DevOps tools**: kubectl, helm, docker, docker-compose
- **Custom utilities**: Aliases, functions, and scripts tailored for productivity

See [`nix/home/zsh/`](nix/home/zsh/) for the zsh config and aliases, [`nix/home/packages.nix`](nix/home/packages.nix) for the tools, and [`home/bin/`](home/bin/) for scripts.

## Quick Start

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/kalindudc/shell/main/install.sh)"
```

Only `curl` is needed. The script:
1. Clones the repository to `~/src/github.com/kalindudc/shell`
2. Installs Nix, and Homebrew on macOS (on Linux, also the system packages in `src/scripts/linux-system.sh`)
3. Applies the flake: `darwinConfigurations.personal` or `.work` on macOS, `homeConfigurations.linux-<arch>` on Linux
4. Installs what Nix does not manage: npm, pi and pipx packages, the GPG signing key, bb and cortex

After that, `task switch` applies a change and `task update` updates the pinned packages.

**Supported platforms**: macOS (Apple silicon), Ubuntu/Debian, Arch Linux

For detailed installation options, see **[Installation Guide](docs/installation.md)**.

## Performance

Shell startup times on modern hardware:
- **Apple Silicon Macs** - Under 400ms
- **Linux systems** - Under 200ms

## Documentation

- **[Installation Guide](docs/installation.md)** - What the installer does, profiles, commands, and adding packages
- **[Architecture](docs/architecture.md)** - The flake, dotfile links, generated files and the Ruby steps
- **[Development](docs/development.md)** - Development setup, testing, and available tasks
- **[Contributing](docs/contributing.md)** - Code standards and testing requirements
- **[Troubleshooting](docs/troubleshooting.md)** - Common issues and solutions

## License

MIT

## Credits

- Homebrew installation patterns: https://github.com/Homebrew/install
- Shell best practices: https://sharats.me/posts/shell-script-best-practices/
