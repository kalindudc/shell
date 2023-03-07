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
alias cpv='rsync -ah --info=progress2'

alias mnt='mount | grep -E ^/dev | column -t'
alias hs='history'
alias cl='clear'
alias psg='ps -ef | grep'
alias myip='curl ip.me'
alias cprof='curl -s -o /dev/null -w "time_namelookup:  %{time_namelookup}s\n time_connect:  %{time_connect}s\n time_appconnect:  %{time_appconnect}s\n time_pretransfer:  %{time_pretransfer}s\n time_redirect:  %{time_redirect}s\n time_starttransfer:  %{time_starttransfer}s\n ----------\n time_total:  %{time_total}s\n"'
alias acceloff='defaults write -g com.apple.mouse.scaling -1'
alias cdiff='code -d'

alias ipseek='/Users/kalindu/.dev/go/1.17/bin/ipseek'
alias hs="history"
alias pf="promformat <(pbpaste | sed 's/$__rate_interval/100M/g') | sed 's/100M/$__rate_interval/g' | pbcopy"
alias lg='lazygit'
