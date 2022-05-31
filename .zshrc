# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export PATH=/opt/homebrew/bin:/opt/homebrew/sbin:$HOME/bin/:$PATH

STARTTIME=$(($(gdate +%s%3N)))

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
  zsh-autosuggestions
  zsh-syntax-highlighting
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

ZSH_AUTOSUGGEST_USE_ASYNC="true"
ZSH_AUTOSUGGEST_STRATEGY=(history completion)

# auto complete one word at a time, similar to '^w' to remove one word at a time
bindkey '^f' forward-word

source $ZSH/oh-my-zsh.sh

[ -f /usr/local/etc/profile.d/autojump.sh ] && . /usr/local/etc/profile.d/autojump.sh

[[ -f /opt/dev/sh/chruby/chruby.sh ]] && type chruby >/dev/null 2>&1 || chruby () { source /opt/dev/sh/chruby/chruby.sh; chruby "$@"; }
if [[ $- == *i* ]] && [[ -f /opt/dev/dev.sh ]]; then source /opt/dev/dev.sh; fi

if [ -f "${HOME}/.gnupg/.gpg-agent-info" ]; then
    . "${HOME}/.gnupg/.gpg-agent-info"
    export GPG_AGENT_INFO
fi

[[ -x /opt/homebrew/bin/brew ]] && eval $(/opt/homebrew/bin/brew shellenv)

autoload -U promptinit; promptinit

source $(brew --prefix)/opt/powerlevel10k/powerlevel10k.zsh-theme
# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

export ZPLUG_HOME=$HOME/.zsh/zplug
source $ZPLUG_HOME/init.zsh

zplug "b4b4r07/enhancd", use:"*init.sh"

if zplug check "b4b4r07/enhancd"; then
  export ENHANCD_FILTER="fzy:fzf"
  export ENHANCD_DOT_SHOW_FULLPATH=1
fi

# Install plugins if there are plugins that have not been installed
if ! zplug check; then
  printf "Some plugins need to be installed. Install plugins? [y/N]: "
  if read -q; then
    echo; zplug install
  fi
fi

# Source plugins and add commands to $PATH
zplug load --verbose

## CUSTOM ##

[ -f /opt/dev/dev.sh ] && source /opt/dev/dev.sh
if [ -e $HOME/.nix-profile/etc/profile.d/nix.sh ]; then . $HOME/.nix-profile/etc/profile.d/nix.sh; fi # added by Nix installer

[[ $BASE_SCRIPT != yes && -f $HOME/src/github.com/kalindudc/shell/src/base.sh ]] && source $HOME/src/github.com/kalindudc/shell/src/base.sh
[[ $KUBERNETES_SCRIPT != yes && -f $HOME/src/github.com/kalindudc/shell/src/kubernetes.sh ]] && source $HOME/src/github.com/kalindudc/shell/src/kubernetes.sh

export PATH=$HOME/bin:$HOME/.kube-plugins:${KREW_ROOT:-$HOME/.krew}/bin:$HOME/go/bin:/usr/bin/local:/usr/local/opt/coreutils/libexec/gnubin:/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/bin:$HOME/.gem/ruby/2.7.2/bin:/opt/rubies/2.7.2/lib/ruby/gems/2.7.0/bin:/opt/rubies/2.7.2/bin:$PATH

ENDTIME=$(($(gdate +%s%3N)))
printf 'Start time %.4fs\n' $(echo "($ENDTIME - $STARTTIME)/1000" | bc -l)


[ -f /opt/dev/dev.sh ] && source /opt/dev/dev.sh
