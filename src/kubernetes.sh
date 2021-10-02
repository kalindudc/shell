#!/bin/bash

KUBERNETES_SCRIPT="yes"

CURRENT_DIR="$(
  cd -- "$(dirname "$0")" >/dev/null 2>&1
  pwd -P
)"

PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"

command -v kubecolor >/dev/null 2>&1 && alias kubectl="kubecolor"

alias k='kubectl'
alias kcl='kubectl'
alias kcln='kubectl --namespace'
alias kclc='kubectl --context'

kdebug() {
  if [[ $# -le 0 ]]; then
    printf "Invalid usage of kdebug\n"
    printf "\nusage: kdebug <context> <namespace>\n\n"
  fi

  kubectl --context "$1" -n "$2" delete pod "$USER-test"
  kubectl --context "$1" -n "$2" run -ti --rm $USER-test --image gcr.io/shopify-docker-images/cloud/debug-container -- bash
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

alias kclgc='kubectl config get-contexts'
