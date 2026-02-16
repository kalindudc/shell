# Troubleshooting

## Installation Fails

```bash
# Remove stale locks
rm -f ./tmp/shell_install.lock ~/.shell_install.lock

# View state
./install.sh --show-state

# Continue or reset
./install.sh --continue
./install.sh --reset-state

# Debug
TRACE=1 ./install.sh 2>&1 | tee install.log
```

## Package Fails

```bash
# Update package manager first
brew update          # macOS
sudo apt-get update  # Ubuntu
sudo pacman -Syu     # Arch

# Try manually
brew install package-name
sudo apt-get install package-name
sudo pacman -S package-name
```

## Shell Not Zsh

```bash
# Check
echo $SHELL

# Set manually
chsh -s /usr/bin/zsh

# Or start manually
exec zsh
```

## Command Not Found

```bash
# Reload shell
source ~/.zshrc
exec zsh

# Check PATH
echo $PATH
which command-name
```

## State Issues

```bash
# View state
cat ~/.shell_install_state

# Reset
./install.sh --reset-state
rm -f ~/.shell_install_state
```

## Platform-Specific

### macOS: Homebrew Not Found

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"  # Apple Silicon
eval "$(/usr/local/bin/brew shellenv)"     # Intel
```

### Ubuntu: GPG Errors

```bash
sudo apt-get install gnupg
./install.sh --continue
```

### Arch: AUR Issues

```bash
# Install yay first
sudo pacman -S --needed base-devel git
git clone https://aur.archlinux.org/yay.git
cd yay && makepkg -si
```

## Complete Uninstall

```bash
# Remove stowed files
stow -D -v -d . -t ~ home

# Remove configs
rm -rf ~/.oh-my-zsh ~/.config/starship.toml

# Reset shell
chsh -s /bin/bash

# Remove repo
rm -rf ~/src/github.com/kalindudc/shell
```
