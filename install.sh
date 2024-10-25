#!/bin/sh

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
  echo "Stowing $HOME..."
  stow home -d "$SHELL_DIR" -t $HOME --adopt
  echo "Done setting up $HOME"
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
  brew install powerlevel10k
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

  brew install --cask visual-studio-code

  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
  #curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash

  pipx install dunk

  echo "Done installing packages"
else
  echo "Skipping brew installation"
fi

echo " "
echo "Installing zsh plugins..."

git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/mroth/evalcache ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/evalcache
git clone https://github.com/b4b4r07/enhancd.git ${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/enhancd
git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions

# kubectl completion
mkdir -p ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/kubectl-autocomplete/
kubectl completion zsh > ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/kubectl-autocomplete/kubectl-autocomplete.plugin.zsh

mkdir -p ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/op-autocomplete/
op completion zsh > ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/op-autocomplete/op-autocomplete.plugin.zsh

echo "Done instaling zsh plugins"

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

echo " "
echo "Setting up $HOME..."

echo "Generating backups for current configs before replacing..."
[[ -f $HOME/.zshrc ]] && echo ".zshrc.bak" && cp $HOME/.zshrc $HOME/.zshrc.bak > /dev/null 2>&1
[[ -f $HOME/.p10k.zsh ]] && echo ".p10k.zsh.bak" && cp $HOME/.p10k.zsh $HOME/.p10k.zsh.bak > /dev/null 2>&1
[[ -f $HOME/.config/direnv ]] && echo ".direnv.bak" && cp $HOME/.config/direnv $HOME/.config/direnv.bak > /dev/null 2>&1
[[ -f $HOME/.vim ]] && echo ".vim.bak" && cp $HOME/.vim $HOME/.vim.bak > /dev/null 2>&1

echo " "
echo "Removing existing configs..."
rm -rf $HOME/.zshrc > /dev/null 2>&1
rm -rf $HOME/.zcompdump > /dev/null 2>&1
rm -rf $HOME/.p10k.zsh > /dev/null 2>&1
rm -rf $HOME/.config/direnv > /dev/null 2>&1
rm -rf $HOME/.vim > /dev/null 2>&1

curl -fLo ~/.vim/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim > /dev/null 2>&1
sh -c 'curl -fLo "${XDG_DATA_HOME:-$HOME/.local/share}"/nvim/site/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim' > /dev/null 2>&1

echo " "
echo "Generate $HOME/.zshrc..."
$SHELL_DIR/src/generate_zshrc.rb
echo "Done generating $HOME/.zshrc"

echo " "
echo "Generate $HOME/.gitconfig..."
# if GIT_EMAIL is not set, prompt for it
if [ -z "$GIT_EMAIL" ]; then
  echo " "
  echo "GIT_EMAIL is not set..."
  read -p "$(echo ${GREEN}Please enter your email address:${NC}) " GIT_EMAIL
  export GIT_EMAIL
  echo " "
fi

# if GIT_NAME is not set, prompt for it
if [ -z "$GIT_NAME" ]; then
  echo " "
  echo "GIT_NAME is not set"
  read -p "$(echo ${GREEN}Please enter your full name:${NC}) " GIT_NAME
  export GIT_NAME
  echo " "
fi

# if GIT_SIGNING_KEY is not set, prompt for it
if [ -z "$GIT_SIGNING_KEY" ]; then
  echo " "
  echo "GIT_SIGNING_KEY is not set"
  read -p "$(echo ${GREEN}please enter your GPG key ID:${NC}) " GIT_SIGNING_KEY
  export GIT_SIGNING_KEY
  echo " "
fi

echo "All set, generating $HOME/.gitconfig..."
$SHELL_DIR/generate_tempate.rb -i $SHELL_DIR/src/templates/.gitconfig.erb -o $SHELL_DIR/shell/home/.gitconfig
echo "Done generating $HOME/.gitconfig"

echo " "
do_stow

echo " "
echo "Setting up git..."

gh auth login
gh auth setup-git

echo "Done setting up git"
echo "All done!"
echo " "
echo " "
echo "If this is the first time you are setting up $SHELL_DIR, you may need to configure powerlevel10k"
if prompt_for_yn "$(echo ${GREEN}Do you want to set up powerlevel10k now?${NC}) (y/N)" "N"; then
  zsh -i -c "p10k configure"
fi
