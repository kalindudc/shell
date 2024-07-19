#!/bin/sh

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
brew install rbenv
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
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

pipx install dunk

echo "Done installing packages"

echo " "
echo "Installing up zsh plugins and zplug..."
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

mkdir -p $HOME/.zplug
git clone https://github.com/zplug/zplug.git $HOME/.zplug
echo "Done instaling zsh plugins and zplug..."

echo " "
echo "Setting up kalindudc/shell..."

git clone https://github.com/kalindudc/shell.git $HOME/src/github.com/kalindudc/shell

echo "Done setting up kalindudc/shell"

echo " "
echo "Setting up $HOME..."

rm -rf $HOME/.zshrc
rm -rf $HOME/.p10k.zsh
rm -rf $HOME/.config/nvim
rm -rf $HOME/.config/direnv
rm -rf $HOME/.vim

curl -fLo ~/.vim/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
sh -c 'curl -fLo "${XDG_DATA_HOME:-$HOME/.local/share}"/nvim/site/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'

echo "Backup $HOME/.zshrc to $HOME/.zshrc.bak"
[[ -f $HOME/.zshrc ]] && cp $HOME/.zshrc $HOME/.zshrc.bak

echo " "
echo "Generate $HOME/.zshrc..."
$HOME/src/github.com/kalindudc/shell/src/generate_zshrc.rb
echo "Done generating $HOME/.zshrc"

echo " "
echo "Generate $HOME/.gitconfig..."
$HOME/src/github.com/kalindudc/shell/src/generate_tempate.rb -i $HOME/src/github.com/kalindudc/shell/src/templates/.gitconfig.erb -o $HOME/src/github.com/kalindudc/shell/home/.gitconfig
echo "Done generating $HOME/.gitconfig"

echo " "
echo "Setting up git..."

gh auth login
gh auth setup-git

echo "Done setting up git"

echo " "
echo "Stowing $HOME..."
stow home -d "$HOME/src/github.com/kalindudc/shell/" -t $HOME --adopt
echo "Done setting up $HOME"
