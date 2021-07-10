#!/bin/bash

FUNC_SCRIPT="yes"

CURRENT_DIR="$(
  cd -- "$(dirname "$0")" >/dev/null 2>&1
  pwd -P
)"

reload() {

  unset BASE_SCRIPT
  unset KUBERNETES_SCRIPT
  unset ALIAS_SCRIPT
  unset FUNC_SCRIPT
  unset GIT_SCRIPT

  [[ $HOME/.zshrc ]] && source $HOME/.zshrc
  # [[ $HOME/.bashrc ]] && source $HOME/.bashrc
}
