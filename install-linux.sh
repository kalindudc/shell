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
  sudo apt install -y zsh
  echo "Switching to zsh..."
  chsh -s $(which zsh)

  echo "Please reboot your machine and run this script again"
  exit 0
fi

if [ "$skip_package_install" = false ]; then
  sudo apt update && suto apt upgrade -y

  # Remove conflicting packages
  sudo apt remove neovim -y

  sudo apt install -y \
    coreutils \
    direnv \
    fd-find \
    fzf \
    fzy \
    gcc \
    gh \
    git \
    gnupg \
    neovim \
    openssl \
    pipx \
    libreadline-dev \
    ripgrep \
    ruby-build \
    sqlite3 \
    stow \
    tcl \
    tk \
    xz-utils \
    zlib1g-dev \
    libssl-dev \
    zlib1g-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    wget \
    curl \
    llvm \
    libncurses5-dev \
    libncursesw5-dev \
    xz-utils \
    tk-dev \
    libffi-dev \
    liblzma-dev \
    python3-openssl \
    xclip \
    flatpak\
    golang \
    gnome-software-plugin-flatpak

  curl -sS https://starship.rs/install.sh | sh

  curl -s https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sudo bash

  curl -s https://api.github.com/repos/dandavison/delta/releases/latest \
    | jq -r '.assets[] | select(.name | test("git-delta.*deb")) | .browser_download_url' \
    | wget -O /tmp/git-delta.deb -i -
  sudo dpkg -i /tmp/git-delta.deb
  rm /tmp/git-delta.deb

  sudo snap install nvim --classic
  sudo snap install task --classic
  sudo snap install helm --classic
  sudo snap install kubectl --classic
  sudo snap install code --classic
  sudo snap install ghostty --classic

  curl https://pyenv.run | bash

  #curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash

  pipx install dunk

  sudo apt --fix-broken install -y

  flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

  echo "Done installing packages"
else
  echo "Skipping brew installation"
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
