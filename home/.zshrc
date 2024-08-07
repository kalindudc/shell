# THIS FILE IS AUTO-GENERATED. DO NOT EDIT THIS FILE DIRECTLY.


#!/bin/bash

export PATH=/opt/homebrew/bin:/opt/homebrew/sbin:$HOME/bin/:$HOME/.local/bin:$HOME/bin:$HOME/.kube-plugins:${KREW_ROOT:-$HOME/.krew}/bin:$HOME/go/bin:/usr/bin/local:/usr/local/opt/coreutils/libexec/gnubin:/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/bin:$HOME/.gem/ruby/2.7.2/bin:/opt/rubies/2.7.2/lib/ruby/gems/2.7.0/bin:/opt/rubies/2.7.2/bin:/opt/homebrew/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/bin/:$PATH

zmodload zsh/zprof
STARTTIME=$(($(gdate +%s%3N)))

# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

source $(brew --prefix)/share/powerlevel10k/powerlevel10k.zsh-theme
# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

### SSH AGENT TO STORE SSH KEY PHRASE
### https://docs.github.com/en/github/authenticating-to-github/connecting-to-github-with-ssh/working-with-ssh-key-passphrases
env=~/.ssh/agent.env

agent_load_env () { test -f "$env" && . "$env" >| /dev/null ; }

agent_start () {
    (umask 077; ssh-agent >| "$env")
    . "$env" >| /dev/null ; }

agent_load_env

# agent_run_state: 0=agent running w/ key; 1=agent w/o key; 2= agent not running
agent_run_state=$(ssh-add -l >| /dev/null 2>&1; echo $?)

if [ ! "$SSH_AUTH_SOCK" ] || [ $agent_run_state = 2 ]; then
    agent_start
    ssh-add
elif [ "$SSH_AUTH_SOCK" ] && [ $agent_run_state = 1 ]; then
    ssh-add
fi

unset env
### END

export ZSH_DISABLE_COMPFIX="false"

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""

plugins=(
  git
  fzf
  history
  colored-man-pages
  colorize
  zsh-completions
  zsh-autosuggestions
  zsh-syntax-highlighting
  evalcache
  enhancd
)

ENHANCD_ENABLE_DOUBLE_DOT="false"
ENHANCD_ENABLE_HOME="false"

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

ZSH_AUTOSUGGEST_USE_ASYNC="true"
ZSH_AUTOSUGGEST_STRATEGY=(history completion)

# auto complete one word at a time, similar to '^w' to remove one word at a time
bindkey '^f' forward-word

source $ZSH/oh-my-zsh.sh

if [ -f "${HOME}/.gnupg/.gpg-agent-info" ]; then
    . "${HOME}/.gnupg/.gpg-agent-info"
    export GPG_AGENT_INFO
fi

[[ -x /opt/homebrew/bin/brew ]] && eval $(/opt/homebrew/bin/brew shellenv)

autoload -U promptinit; promptinit

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

## dev ##

[[ -f /opt/dev/sh/chruby/chruby.sh ]] && type chruby >/dev/null 2>&1 || chruby () { source /opt/dev/sh/chruby/chruby.sh; chruby "$@"; }
if [[ $- == *i* ]] && [[ -f /opt/dev/dev.sh ]]; then source /opt/dev/dev.sh; fi
[ -f /opt/dev/dev.sh ] && source /opt/dev/dev.sh
if [ -e $HOME/.nix-profile/etc/profile.d/nix.sh ]; then . $HOME/.nix-profile/etc/profile.d/nix.sh; fi # added by Nix installer

if which direnv > /dev/null; then _evalcache direnv hook zsh; fi

# PYENV
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
_evalcache pyenv init -

# if rvenv is installed then load it
if which rbenv > /dev/null; then _evalcache rbenv init -; fi

source <(helm completion zsh)

fpath=($HOME/.zsh ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions/src $fpath)
autoload -Uz compinit
compinit -u

### TEMPLATES ###

# bases template

BASE_SCRIPT="yes"

HISTTIMEFORMAT="%d/%m/%y %T "
HISTSIZE=20000
HISTFILESIZE=20000


# bases template end

# aliases template

ALIAS_SCRIPT="yes"

export EDITOR="nvim"

alias edit="nvim"
alias e="nvim"
alias nv="neovide"

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
alias pf="promformat <(pbpaste | sed 's/\$__rate_interval/100M/g') | sed 's/100M/\$__rate_interval/g' | pbcopy"
alias lg='lazygit'
alias ls='ls --color=auto'


# aliases template end

# git template

export GPG_TTY=$(tty)

GIT_SCRIPT="yes"

alias g='git'
alias gs='git stash'
alias gsp='git stash pop'
alias gsd='git stash drop'
alias gssd='git stash && git stash drop'
alias gd='git dunk'
alias gpull='git pull origin $(git rev-parse --abbrev-ref HEAD)'
alias grpull='git pull --rebase origin $(git rev-parse --abbrev-ref HEAD)'

GIT_PROJECTS_PATH="$HOME/src/github.com/"


unalias grb
grb() {
  count="${1:=2}"
  git rebase -i $(git rev-parse --abbrev-ref HEAD)~$count
}

gfp() {
  git push origin +$(git rev-parse --abbrev-ref HEAD)
}

gacp() {

  if [[ $# -eq 2 ]]; then
    printf "adding \`$1\` and commiting with \`$2\`\n"
    git add $1
    git commit -m $2
  fi

  if [[ $# -eq 1 ]]; then
    printf "commiting with $1\n"
    git commit -m $1
  fi

  git push origin $(git rev-parse --abbrev-ref HEAD)
}
unalias gp
alias gp='gacp'

# functions
gitcd() {
  dir=""

  if [[ $# -gt 0  ]]; then
    dir=$(ls -a $GIT_PROJECTS_PATH | grep $@ | sed 's/\x1b\[[0-9;]*m//g' | head -n 1)
    [[ -z $dir  ]] && printf "Could not find matching directory\n" || printf "Found matching directory: $dir\n"
  fi

  cd "${GIT_PROJECTS_PATH}${dir}"
}

ghopen() {
  url_to_open="$(git remote get-url origin)"
  printf "$url_to_open\n"
  open "$url_to_open"
}


# git template end

# functions template

FUNC_SCRIPT="yes"

reload() {

  exec zsh
}


# functions template end

# kubernetes template

KUBERNETES_SCRIPT="yes"

export KUBE_EDITOR="nvim"

#source <(kubectl completion zsh)
source <(eval HTTPS_PROXY=1:1 kubectl completion zsh)
# command -v kubecolor >/dev/null 2>&1 && alias kubectl="kubecolor"
# compdef kubecolor=kubectl

alias k='kubectl'
alias kcl='kubectl'
alias kngx='kubectl ingress-nginx --deployment nginx-ingress-controller'
alias kevents="kubectl get events --sort-by='.lastTimestamp'"
alias kclgc="kubectl config get-contexts -o name | fzf --exact -m --height=40% | tr -d '\n' | pbcopy; pbpaste; echo ''"
alias klog="stern $@"
alias kcls="kubectl config get-contexts -o name | grep -e "

kdebug() {
  if [[ $# -le 0 ]]; then
    printf "Invalid usage of kdebug\n"
    printf "\nusage: kdebug <context> <namespace>\n\n"
    return 1
  fi

  kubectl --context "$1" -n "$2" delete pod "$USER-test"
  kubectl --context "$1" -n "$2" run -ti --rm $USER-test --image gcr.io/shopify-docker-images/cloud/debug-container -- bash
}

kcerts() {
  if [[ $# -le 2 ]]; then
    printf "Invalid usage of kcerts\n"
    printf "\nusage: kcerts <context> <namespace> <secret>\n\n"
    return 1
  fi

  kubectl --context $1 --namespace $2 get secrets $3 -o json | jq -r '.data["tls.crt"]' | base64 --decode | openssl x509 -noout -text
}

kclcn() {
  context=$1
  shift
  namespace=$1
  shift
  kubectl --namespace $namespace --context $context $@

}

kcla() {
  kubectl $@ -A
}

kexec() {
  cluster=$(kubectl config get-contexts -o name | fzf)
  if [[ -z "$cluster" ]] then
    echo "Please select a valid cluster"
    return -1
  fi

  namespace=$(kubectl --context $cluster get ns -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | fzf)
  if [[ -z "$namespace" ]] then
    echo "Please select a valid namespace"
    return -1
  fi

  deploy=$(kubectl --context $cluster -n $namespace get deploy -o name | fzf)
  if [[ -z "$namespace" ]] then
    echo "Please select a valid namespace"
    return -1
  fi

  kubectl --context $cluster -n $namespace exec -it $deploy -- bash
}


# cloudplatform: add Shopify clusters to your local kubernetes config
export KUBECONFIG=${KUBECONFIG:+$KUBECONFIG:}/Users/kalindu/.kube/config:/Users/kalindu/.kube/config.shopify.cloudplatform

# kubernetes template end

### TEMPLATES END ###

ENDTIME=$(($(gdate +%s%3N)))
printf 'Start time %.4fs\n' $(echo "($ENDTIME - $STARTTIME)/1000" | bc -l)