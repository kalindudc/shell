#!/bin/sh

CURRENT_DIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

reload() {
  [[ $HOME/.zshrc ]] && source $HOME/.zshrc
  # [[ $HOME/.bashrc ]] && source $HOME/.bashrc
}

newbranch() {
  if [[ $# -gt 0 ]]; then
    git checkout -b $1
    export BRANCH=$1
  else
    echo "Invalid use of \`newbranch\`. Please provide a name for the new branch."
  fi
}

checkout() {
  if [[ $# -gt 0 ]]; then
    git checkout $1
    export BRANCH=$1
  else
    echo "Invalid use of \`checkout\`. Please provide a name for the new branch."
  fi
}