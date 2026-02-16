# Installation

## Quick Install

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/kalindudc/shell/main/install.sh)"
```

Requires: `curl`, `git (auto-installed if missing)`

## Options

```bash
# Skip categories
./install.sh --skip-category=fonts
./install.sh --skip-category=optional

# Non-interactive
NONINTERACTIVE=1 GIT_EMAIL="you@example.com" GIT_NAME="Your Name" ./install.sh

# Debug
TRACE=1 ./install.sh

# Resume or reset
./install.sh --continue
./install.sh --reset-state
./install.sh --show-state
```

## Categories

| Category | Packages |
|----------|----------|
| `core` | git, curl, wget, stow, ruby, gpg |
| `shell` | zsh, fzf, ripgrep, zoxide, fd, direnv, starship |
| `dev` | neovim, gh, gcc, go-task, git-delta, jq |
| `runtimes` | go, pyenv, nvm |
| `devops` | kubectl, helm, docker |
| `fonts` | Nerd Fonts |
| `optional` | vscode, ghostty, 1password-cli, lazygit |

## After Install

```bash
exec zsh  # Restart shell

# Verify
starship --version
fzf --version
nvim --version
```
