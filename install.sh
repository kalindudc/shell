#!/bin/sh

mkdir -p $HOME/src/github.com/kalindudc

brew tap homebrew/cask-fonts
brew instal gh gpg fzy fzf kubectl coreutils git pipx nvim fd jesseduffield/lazygit/lazygit font-hack-nerd-font rg neovide
brew install --cask visual-studio-code
brew install romkatv/powerlevel10k/powerlevel10k
sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
curl https://bun.sh/install | bash
curl -fsSL https://deno.land/x/install/install.sh | sh

pipx install dunk

gh auth login
gh auth setup-git

git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

mkdir -p $HOME/.zplug
git clone https://github.com/zplug/zplug.git $HOME/.zplug

git clone https://github.com/kalindudc/shell.git $HOME/src/github.com/kalindudc/shell

rm -rf $HOME/.zshrc
rm -rf $HOME/.p10k.zsh
rm -rf $HOME/.config/nvim

curl -fLo ~/.vim/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
sh -c 'curl -fLo "${XDG_DATA_HOME:-$HOME/.local/share}"/nvim/site/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'

cp $HOME/src/github.com/kalindudc/shell/.zshrc $HOME/.zshrc
cp $HOME/src/github.com/kalindudc/shell/.p10k.zsh $HOME/.p10k.zsh
ln -s $HOME/src/github.com/kalindudc/shell/nvim $HOME/.config/nvim
ln -s $HOME/src/github.com/kalindudc/shell/.vim $HOME/.vim
