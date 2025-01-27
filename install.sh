#!/usr/bin/env bash

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

skip_brew=false
# Function to display usage
usage() {
  echo "Usage: $0 [--skip-brew] [--stow] [--help]"
  exit 1
}

do_stow() {
  $SHELL_DIR/src/setup.sh --stow
}

# Parse options
while [[ "$#" -gt 0 ]]; do
  case $1 in
    --skip-brew)
      skip_brew=true
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

if [ "$skip_brew" = false ]; then
  brew update
  brew upgrade

  # Install packages
  echo "Installing packages..."

  brew install coreutils
  brew install direnv
  brew install fd
  brew install font-hack-nerd-font
  brew install fzf
  brew install fzy
  brew install gcc
  brew install gh
  brew install git
  brew install gpg
  brew install helm
  brew install jesseduffield/lazygit/lazygit
  brew install kubectl
  brew install neovim
  brew install openssl
  brew install pipx
  brew install pyenv
  #brew install rbenv
  brew install readline
  brew install rg
  brew install ruby-build
  brew install sqlite3
  brew install stow
  brew install tcl-tk
  brew install xz
  brew install zlib
  brew install zoxide
  brew install 1password-cli
  brew install go-task
  brew install git-delta

  brew install --cask visual-studio-code

  # install fonts
  brew search '/font-.*-nerd-font/' | awk '{ print $1 }' | xargs -I{} brew install --cask {} || true

  curl -sS https://starship.rs/install.sh | sh

  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
  #curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash

  pipx install dunk

  echo "Done installing packages"
else
  echo "Skipping brew installation"
fi

echo " "
echo "Setting up $SHELL_DIR..."

# Check if the directory exists
if [ -d "$SHELL_DIR" ]; then
  if prompt_for_yn "$(echo ${GREEN}$SHELL_DIR exists, do you want to overwrite the changes wiith upstream changes?${NC}) (y/N)" "N"; then
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
  git clone "$REPO_URL" "$SHELL_DIR"
fi

echo "Done setting up $SHELL_DIR"

# starting setup
$SHELL_DIR/src/setup.sh
