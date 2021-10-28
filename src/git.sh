#!/bin/bash

export GPG_TTY=$(tty)

GIT_SCRIPT="yes"

alias g='git'

GIT_PROJECTS_PATH="/home/kalindu/src/github.com/"

git config --global user.name "Kalindu De Costa"
git config --global user.email "kalindu.decosta@shopify.com"
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

unalias grb

grb() {
  git rebase -i $(git rev-parse --abbrev-ref HEAD)~$1
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

# functions
gitcd() {
  dir=""

  if [[ $# -gt 0  ]]; then
    dir=$(ls -a $GIT_PROJECTS_PATH | grep $@ | sed 's/\x1b\[[0-9;]*m//g' | head -n 1)
    [[ -z $dir  ]] && printf "Could not find matching directory\n" || printf "Found matching directory: $dir\n"
  fi

  cd "${GIT_PROJECTS_PATH}${dir}"
}

clone() {
  if [[ $# -le 0 ]]; then
    printf "You must specify a repository to clone.\n\n"
    printf "usage: clone <repo> [<path> || $GIT_PROJECT_PATH]\n\n"
    return -1
  fi

  repo="$1"
  [[ $# -gt 2 ]] && root_path="$2" || root_path="$GIT_PROJECTS_PATH"
  # default to kalindudc/<repo>
  if [[ $repo =~ (^[^\/]+)[^.git]$ ]]; then
    repo="git@github.com:kalindudc/${repo}.git"
  # otherwise try <org>/<repo>
  elif [[ $repo =~ (.+)\/(.+)[^.git]$ ]]; then
    repo="git@github.com:${repo}.git"
  fi

  printf "Cloning: $repo\n"

  # else clone with given repo
  git -C "$root_path" clone "$repo" && gitcd "$(basename "$repo" .git)"
}

ghopen() {
  url_to_open="$(git remote get-url origin | sed -e's/:/\//' -e 's/git@/http:\/\//')"
  printf "$url_to_open\n"
  python -mwebbrowser "$url_to_open"
}
