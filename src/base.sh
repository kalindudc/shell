#!/bin/sh

BASE_SCRIPT="yes"

CURRENT_DIR="$(
  cd -- "$(dirname "$0")" >/dev/null 2>&1
  pwd -P
)"

PATH=$CURRENT_DIR/bin:$PATH
HISTTIMEFORMAT="%d/%m/%y %T "


[[ $ALIAS_SCRIPT != yes && -f $CURRENT_DIR/aliases.sh ]] && source $CURRENT_DIR/aliases.sh
[[ $FUNC_SCRIPT != yes && -f $CURRENT_DIR/functions.sh ]] && source $CURRENT_DIR/functions.sh
[[ $GIT_SCRIPT != yes && -f $CURRENT_DIR/git.sh ]] && source $CURRENT_DIR/git.sh
