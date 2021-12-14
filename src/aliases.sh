#!/bin/bash

ALIAS_SCRIPT="yes"

CURRENT_DIR="$(
  cd -- "$(dirname "$0")" >/dev/null 2>&1
  pwd -P
)"

MY_BASH_BLUE="\033[0;34m" #Blue
MY_BASH_NOCOLOR="\033[0m"
HISTTIMEFORMAT=`echo -e ${MY_BASH_BLUE}[%F %T] $MY_BASH_NOCOLOR `
HISTSIZE=20000
HISTFILESIZE=20000

alias grepn='grep -n'

# terminal multiplexers
alias tmux='tmux -CC'

# file manipulations
alias ls='ls -F --color=yes'
alias ll='ls -lh --color=yes'
alias lsg='lsa --color=yes | grep -i $@ '
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
