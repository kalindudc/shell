#!/usr/bin/env bash

# ============================================================================
# DEPRECATED: This script is no longer maintained.
# Please use the unified install.sh in the root directory instead.
# See docs/legacy/README.md for migration instructions.
# ============================================================================

cat <<'EOF'
╔═══════════════════════════════════════════════════════════════════════════╗
║                          DEPRECATION WARNING                              ║
╚═══════════════════════════════════════════════════════════════════════════╝

This installation script has been DEPRECATED and is no longer maintained.

Please use the new unified installation script:

    cd ../.. && ./install.sh

Benefits of the new script:
  - Auto-detects your operating system
  - Resume from failed steps
  - Modular and maintainable
  - Comprehensive testing

For more information, see: docs/legacy/README.md

EOF

read -p "Press Ctrl+C to exit, or Enter to continue with this deprecated script..." 

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

prompt_for_yn() {
  local prompt="$1"
  local default="$2"
  local answer

  while true; do
    read -p "$prompt " answer
    answer=${answer:-$default}

    case "$answer" in
      [Yy]* ) return 0;;
      [Nn]* ) return 1;;
      * ) echo "Please answer y or N.";;
    esac
  done
}

GIT_CLONE_DIR="$HOME/src/github.com/kalindudc"
SHELL_DIR="$GIT_CLONE_DIR/shell"
SHELL_REMOTE="https://github.com/kalindudc/shell.git"

mkdir -p $GIT_CLONE_DIR

skip_package_install=false
# Function to display usage
usage() {
  echo "Usage: $0 [--skip-packages] [--stow] [--help]"
  exit 1
}

do_stow() {
  $SHELL_DIR/src/setup.sh --stow
}

# Parse options
while [ "$#" -gt 0 ]; do
  case $1 in
    --skip-packages)
      skip_package_install=true
      ;;
    -h|--help)
      usage
      ;;
    --stow)
      do_stow
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
  shift
done

if [ "$SHELL" != "/usr/bin/zsh" ]; then
  echo "Zsh is not the default shell. Installing zsh..."
  sudo pacman -S --noconfirm zsh
  echo "Switching to zsh..."
  chsh -s $(which zsh)

  echo "Please reboot your machine and run this script again"
  exit 0
fi

# Check if yay is installed, if not install it
if ! command -v yay &> /dev/null; then
  echo "yay AUR helper not found. Installing yay..."
  sudo pacman -S --needed --noconfirm git base-devel
  git clone https://aur.archlinux.org/yay.git /tmp/yay
  cd /tmp/yay
  makepkg -si --noconfirm
  cd -
  rm -rf /tmp/yay
  echo "yay installed successfully"
fi

if [ "$skip_package_install" = false ]; then
  sudo pacman -Syu --noconfirm

  # Install packages from official repositories
  echo "Installing packages from official repositories..."
  sudo pacman -S --needed --noconfirm \
    coreutils \
    direnv \
    fd \
    fzf \
    gcc \
    git \
    github-cli \
    gnupg \
    go \
    neovim \
    openssl \
    python-pipx \
    readline \
    ripgrep \
    ruby \
    sqlite \
    stow \
    tcl \
    tk \
    wget \
    curl \
    xclip \
    xz \
    zlib \
    bzip2 \
    ncurses \
    flatpak \
    jq \
    base-devel \
    bc

  gem instal erb
  gem install bundler

  # Install packages from AUR
  echo "Installing packages from AUR..."
  yay -S --needed --noconfirm \
    starship \
    zoxide \
    git-delta \
    helm \
    kubectl \
    visual-studio-code-bin \
    ghostty \
    go-task-bin \
    nvm

  # Install snap support (optional on Arch)
  if prompt_for_yn "$(echo ${GREEN}Do you want to install snapd for snap package support?${NC}) (y/N)" "N"; then
    yay -S --needed --noconfirm snapd
    sudo systemctl enable --now snapd.socket
    sudo ln -sf /var/lib/snapd/snap /snap
    echo "snapd installed and enabled"
  fi

  # Install pyenv
  echo "Installing pyenv..."
  curl https://pyenv.run | bash

  # Install NVM (Node Version Manager)
  echo "Installing NVM..."
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash

  # Install dunk via pipx
  echo "Installing dunk..."
  pipx install dunk

  # Setup flatpak
  echo "Setting up flatpak..."
  flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

  # Install Nerd Fonts (optional)
  if prompt_for_yn "$(echo ${GREEN}Do you want to install Nerd Fonts?${NC}) (y/N)" "N"; then
    yay -S --needed --noconfirm \
      ttf-hack-nerd \
      ttf-firacode-nerd \
      ttf-jetbrains-mono-nerd \
      ttf-meslo-nerd \
      ttf-sourcecodepro-nerd
    echo "Nerd Fonts installed"
  fi

  echo "Done installing packages"
else
  echo "Skipping package installation"
fi

echo " "
echo "Setting up $SHELL_DIR..."

# Check if the directory exists
if [ -d "$SHELL_DIR" ]; then
  if prompt_for_yn "$(echo ${GREEN}$SHELL_DIR exists, do you want to overwrite the changes with upstream changes?${NC}) (y/N)" "N"; then
    echo "Directory exists. Navigating to $SHELL_DIR."
    cd "$SHELL_DIR" || exit

    # Discard any changes
    echo "Discarding any local changes."
    git reset --hard
    git clean -fd

    # Pull the latest changes
    echo "Pulling the latest changes."
    git pull origin main
  else
    echo "Skipping $SHELL_DIR"
  fi
else
  # Clone the repository
  echo "$SHELL_DIR does not exist. Cloning the repository."
  git clone "$SHELL_REMOTE" "$SHELL_DIR"
fi

echo "Done setting up $SHELL_DIR"

# start setup.sh
$SHELL_DIR/src/setup.sh
