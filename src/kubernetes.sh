#!/bin/bash

KUBERNETES_SCRIPT="yes"

CURRENT_DIR="$(
  cd -- "$(dirname "$0")" >/dev/null 2>&1
  pwd -P
)"

PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"

source <(kubectl completion zsh)
# command -v kubecolor >/dev/null 2>&1 && alias kubectl="kubecolor"
# compdef kubecolor=kubectl

alias k='kubectl'
alias kcl='kubectl'
alias kngx='kubectl ingress-nginx --deployment nginx-ingress-controller'
alias kevents="kubectl get events --sort-by='.lastTimestamp'"
alias kclgc="kubectl config get-contexts -o name | fzf --exact -m --height=40% | tr -d '\n' | pbcopy; pbpaste; echo ''"
alias klog="stern $@"

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
