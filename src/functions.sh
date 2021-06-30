#!/bin/sh

CURRENT_DIR="$(
  cd -- "$(dirname "$0")" >/dev/null 2>&1
  pwd -P
)"

reload() {
  [[ $HOME/.zshrc ]] && source $HOME/.zshrc
  # [[ $HOME/.bashrc ]] && source $HOME/.bashrc
}
