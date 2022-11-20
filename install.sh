#!/bin/sh

mkdir -p $HOME/src/github.com/kalindudc

brew instal gh gpg fzy fzf kubectl coreutils git
brew install --cask visual-studio-code
brew install romkatv/powerlevel10k/powerlevel10k
sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

gh auth login
gh auth setup-git

git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting

mkdir -p $HOME/.zplug
git clone https://github.com/zplug/zplug.git $HOME/.zplug

git clone https://github.com/kalindudc/shell.git $HOME/src/github.com/kalindudc/shell

rm $HOME/.zshrc
cp $HOME/src/github.com/kalindudc/shell/.zshrc $HOME/.zshrc
cp $HOME/src/github.com/kalindudc/shell/.p10k.zsh $HOME/.p10k.zsh
