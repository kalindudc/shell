#!/bin/bash

BASE_SCRIPT="yes"

CURRENT_DIR="$(
  cd -- "$(dirname "$0")" >/dev/null 2>&1
  pwd -P
)"

HISTTIMEFORMAT="%d/%m/%y %T "

[[ $FUNC_SCRIPT != yes && -f $CURRENT_DIR/functions.sh ]] && source $CURRENT_DIR/functions.sh
[[ $ALIAS_SCRIPT != yes && -f $CURRENT_DIR/aliases.sh ]] && source $CURRENT_DIR/aliases.sh
[[ $GIT_SCRIPT != yes && -f $CURRENT_DIR/git.sh ]] && source $CURRENT_DIR/git.sh
