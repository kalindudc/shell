#!/bin/bash

ALIAS_SCRIPT="yes"

CURRENT_DIR="$(
  cd -- "$(dirname "$0")" >/dev/null 2>&1
  pwd -P
)"

HISTSIZE=20000
HISTFILESIZE=20000

alias grepn='grep -n'

# terminal multiplexers
alias tmux='tmux -CC'

# file manipulations
alias ls='exa'
alias cpv='rsync -ah --info=progress2'

alias mnt='mount | grep -E ^/dev | column -t'
alias hs='custom-history'
alias cl='clear'
alias psg='ps -ef | grep'
alias myip='curl ip.me'

custom-history() {
  if [[ $# -lt 1 ]]; then
    history -i
  else
    history -i | grep $@
  fi
}
