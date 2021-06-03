#!/bin/sh

CURRENT_DIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

export PATH=$CURRENT_DIR/bin:$PATH

source $CURRENT_DIR/aliases.sh
source $CURRENT_DIR/functions.sh