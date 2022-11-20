#!/bin/bash

export GPG_TTY=$(tty)

GIT_SCRIPT="yes"

alias g='git'

GIT_PROJECTS_PATH="$HOME/src/github.com/"

git config --global user.name "Kalindu De Costa"
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
git config --global alias.p 'push origin $(git rev-parse --abbrev-ref HEAD)'
git config --global alias.co 'checkout'
git config --global alias.nb 'checkout -b'
git config --global core.excludesfile ~/.gitignore

git config --global core.pager delta
git config --global interactive.diffFilter 'delta --color-only --features=interactive'

git config --global delta.features 'side-by-side line-numbers decorations'
git config --global delta.syntax-theme Dracula
git config --global delta.plus-style "syntax '#003800'"
git config --global delta.minus-style "syntax '#3f0001'"

git config --global delta.decorations.commit-decoration-style 'bold yellow box ul'
git config --global delta.decorations.file-style 'bold yellow ul'
git config --global delta.file-decoration-style none
git config --global delta.hunk-header-decoration-style 'cyan box ul'

git config --global delta.line-numbers.line-numbers-left-style cyan
git config --global delta.line-numbers.line-numbers-right-style cyan
git config --global delta.line-numbers.line-numbers-minus-style 124
git config --global delta.line-numbers.line-numbers-plus-style 28

git config --global commit.gpgsign true

unalias grb

grb() {
  count="${1:=2}"
  git rebase -i $(git rev-parse --abbrev-ref HEAD)~$count
}

gfp() {
  git push origin +$(git rev-parse --abbrev-ref HEAD)
}

gacp() {

  if [[ $# -eq 2 ]]; then
    printf "adding \`$1\` and commiting with \`$2\`\n"
    git add $1
    git commit -m $2
  fi

  if [[ $# -eq 1 ]]; then
    printf "commiting with $1\n"
    git commit -m $1
  fi

  git push origin $(git rev-parse --abbrev-ref HEAD)
}
unalias gp
alias gp='gacp'

# functions
gitcd() {
  dir=""

  if [[ $# -gt 0  ]]; then
    dir=$(ls -a $GIT_PROJECTS_PATH | grep $@ | sed 's/\x1b\[[0-9;]*m//g' | head -n 1)
    [[ -z $dir  ]] && printf "Could not find matching directory\n" || printf "Found matching directory: $dir\n"
  fi

  cd "${GIT_PROJECTS_PATH}${dir}"
}

ghopen() {
  url_to_open="$(git remote get-url origin | sed -e's/:/\//' -e 's/git@/http:\/\//')"
  printf "$url_to_open\n"
  python -mwebbrowser "$url_to_open"
}
