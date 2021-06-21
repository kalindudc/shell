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

gitpush() {

  if [[ $# -eq 2 ]]; then
    echo "adding $1 and commiting with $2"
    git add $1
    git commit -m $2
  fi

  if [[ $# -eq 1 ]]; then
    echo "commiting with $1"
    git commit -m $1
  fi

  git push origin $(git branch --show-current)
}