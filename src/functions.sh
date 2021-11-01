#!/bin/bash

FUNC_SCRIPT="yes"

CURRENT_DIR="$(
  cd -- "$(dirname "$0")" >/dev/null 2>&1
  pwd -P
)"

reload() {

  exec zsh
}

setbin() {
  export PATH=$CURRENT_DIR/bin:$PATH
}
