#!/bin/sh

CURRENT_DIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

# terminal multiplexers
alias tmux='tmux -CC'

# file manipulations
alias ls='ls -F --color=yes'
alias ll='ls -lh --color=yes'
alias lsg='lsa --color=yes | grep -i $@ '
alias cpv='rsync -ah --info=progress2'

alias mnt='mount | grep -E ^/dev | column -t'
alias gh='history|grep'
alias cl='clear'
alias psg='ps -ef | grep'
alias myip='curl ip.me'