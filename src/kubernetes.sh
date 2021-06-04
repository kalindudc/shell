#!/bin/sh

CURRENT_DIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

[[ /usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/bin/kubectl ]] && source <(kubectl completion zsh)

command -v kubecolor >/dev/null 2>&1 && alias kubectl="kubecolor"

alias kcl='kubectl $@'
alias kcln='kubectl --namespace $@'
alias kclc='kubectl --context $@'

kclcn() {
    context=$1
    shift
    namespace=$1
    shift
    kubectl --namespace $namespace --context $context $@
        
}


