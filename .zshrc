export ZSH="/home/kalindu/.oh-my-zsh"

ZSH_THEME="dracula"

plugins=(
  git
  zsh-autosuggestions
  zsh-syntax-highlighting
  kubectl
)

# This speeds up pasting w/ autosuggest
# https://github.com/zsh-users/zsh-autosuggestions/issues/238
pasteinit() {
  OLD_SELF_INSERT=${${(s.:.)widgets[self-insert]}[2,3]}
  zle -N self-insert url-quote-magic # I wonder if you'd need `.url-quote-magic`?
}

pastefinish() {
  zle -N self-insert $OLD_SELF_INSERT
}
zstyle :bracketed-paste-magic paste-init pasteinit
zstyle :bracketed-paste-magic paste-finish pastefinish
# slow pastes

source $ZSH/oh-my-zsh.sh

[[ $BASE_SCRIPT != yes && -f /home/kalindu/src/github.com/shell/src/base.sh ]] && source /home/kalindu/src/github.com/shell/src/base.sh
[[ $KUBERNETES_SCRIPT != yes && -f /home/kalindu/src/github.com/shell/src/kubernetes.sh ]] && source /home/kalindu/src/github.com/shell/src/kubernetes.sh

export NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh" # This loads nvm

nvm use v16.4.2 > /dev/null
