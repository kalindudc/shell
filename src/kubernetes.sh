#!/bin/bash

KUBERNETES_SCRIPT="yes"

CURRENT_DIR="$(
  cd -- "$(dirname "$0")" >/dev/null 2>&1
  pwd -P
)"

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
