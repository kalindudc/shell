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

export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="dracula"

plugins=(
  git
  history
  colored-man-pages
  colorize
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

ZSH_AUTOSUGGEST_USE_ASYNC="true"
ZSH_AUTOSUGGEST_STRATEGY=(history completion)

# auto complete one word at a time, similar to '^w' to remove one word at a time
bindkey '^f' forward-word

source $ZSH/oh-my-zsh.sh

[ -f /usr/local/etc/profile.d/autojump.sh ] && . /usr/local/etc/profile.d/autojump.sh

[[ $BASE_SCRIPT != yes && -f /home/kalindu/src/github.com/shell/src/base.sh ]] && source /home/kalindu/src/github.com/shell/src/base.sh
[[ $KUBERNETES_SCRIPT != yes && -f /home/kalindu/src/github.com/shell/src/kubernetes.sh ]] && source /home/kalindu/src/github.com/shell/src/kubernetes.sh

[[ -f /opt/dev/sh/chruby/chruby.sh ]] && type chruby >/dev/null 2>&1 || chruby () { source /opt/dev/sh/chruby/chruby.sh; chruby "$@"; }
if [[ $- == *i* ]] && [[ -f /opt/dev/dev.sh ]]; then source /opt/dev/dev.sh; fi

if [ -f "${HOME}/.gnupg/.gpg-agent-info" ]; then
    . "${HOME}/.gnupg/.gpg-agent-info"
    export GPG_AGENT_INFO
fi

[[ -x /usr/local/bin/brew ]] && eval $(/usr/local/bin/brew shellenv)

autoload -U promptinit; promptinit

zstyle :prompt:pure:git:stash show yes

prompt pure

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

export ZPLUG_HOME=/usr/local/opt/zplug
source $ZPLUG_HOME/init.zsh

zplug "b4b4r07/enhancd", use:"*init.sh"

if zplug check "b4b4r07/enhancd"; then
  export ENHANCD_FILTER="fzf"
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

ENDTIME=$(($(gdate +%s%3N)))
printf 'Start time %.4fs\n' $(echo "($ENDTIME - $STARTTIME)/1000" | bc -l)
