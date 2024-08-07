#!/bin/sh

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

mkdir -p $HOME/src/github.com/kalindudc

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
brew install neovide
brew install nvim
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

brew install --cask visual-studio-code

sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
#curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash

pipx install dunk

echo "Done installing packages"

echo " "
echo "Installing zsh plugins..."

git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/mroth/evalcache ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/evalcache
git clone https://github.com/b4b4r07/enhancd.git ${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/enhancd
git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions

echo "Done instaling zsh plugins"

echo " "
echo "Setting up kalindudc/shell..."

git clone https://github.com/kalindudc/shell.git $HOME/src/github.com/kalindudc/shell

echo "Done setting up kalindudc/shell"

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
rm -rf $HOME/.p10k.zsh > /dev/null 2>&1
rm -rf $HOME/.config/direnv > /dev/null 2>&1
rm -rf $HOME/.vim > /dev/null 2>&1

curl -fLo ~/.vim/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim > /dev/null 2>&1
sh -c 'curl -fLo "${XDG_DATA_HOME:-$HOME/.local/share}"/nvim/site/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim' > /dev/null 2>&1

echo " "
echo "Generate $HOME/.zshrc..."
$HOME/src/github.com/kalindudc/shell/src/generate_zshrc.rb
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
$HOME/src/github.com/kalindudc/shell/src/generate_tempate.rb -i $HOME/src/github.com/kalindudc/shell/src/templates/.gitconfig.erb -o $HOME/src/github.com/kalindudc/shell/home/.gitconfig
echo "Done generating $HOME/.gitconfig"

echo " "
echo "Stowing $HOME..."
stow home -d "$HOME/src/github.com/kalindudc/shell/" -t $HOME --adopt
echo "Done setting up $HOME"

echo " "
echo "Setting up git..."

gh auth login
gh auth setup-git

echo "Done setting up git"
echo "All done!"
zsh
