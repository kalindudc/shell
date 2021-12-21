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
alias hs='history'
alias cl='clear'
alias psg='ps -ef | grep'
alias myip='curl ip.me'
alias cprof='curl -s -o /dev/null -w "time_namelookup:  %{time_namelookup}s\n time_connect:  %{time_connect}s\n time_appconnect:  %{time_appconnect}s\n time_pretransfer:  %{time_pretransfer}s\n time_redirect:  %{time_redirect}s\n time_starttransfer:  %{time_starttransfer}s\n ----------\n time_total:  %{time_total}s\n"'
