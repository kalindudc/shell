#!/bin/sh

alias g='git'

git config --global alias.st 'status'
git config --global alias.b 'branch --show-current'
git config --global alias.c 'commit -m'
git config --global alias.a 'add'
git config --global alias.aa 'add -A'
git config --global alias.au 'add -u'
git config --global alias.last 'log -1 HEAD --stat'
git config --global alias.rv 'remote -v'
git config --global alias.d 'diff'
git config --global alias.dv 'difftool -t vimdiff -y'
git config --global alias.gl 'config --global -l'
