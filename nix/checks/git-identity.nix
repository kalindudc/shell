# Every repo gets the main identity and this machine's signing key; the private repo's
# conditional includes switch work repos to the work identity.
{ pkgs, gitConfig }:
pkgs.runCommand "git-identity" { nativeBuildInputs = [ pkgs.git ]; } ''
  export HOME=$PWD/home GIT_CONFIG_NOSYSTEM=1
  mkdir -p $HOME/.config/git $HOME/src/github.com/kalindudc/shell-private/git
  cp ${gitConfig} $HOME/.config/git/config
  git config --file $HOME/.config/git/signing user.signingkey MAINKEY
  # Home Manager's activation creates an empty ~/.gitconfig (nix/home/git.nix), so a tool's
  # write lands there rather than in the read-only ~/.config/git/config.
  touch $HOME/.gitconfig
  git config --global maintenance.auto false
  grep -q 'maintenance' $HOME/.gitconfig

  check() {
    actual=$(git -C "$1" config "$2")
    if [ "$actual" != "$3" ]; then
      echo "$1: $2 is '$actual', expected '$3'" >&2
      exit 1
    fi
  }
  repo() {
    git init -q "$HOME/$1"
    if [ -n "''${2:-}" ]; then git -C "$HOME/$1" remote add origin "$2"; fi
  }

  repo src/mine https://github.com/jane/mine.git
  repo src/work https://github.com/example-corp/app.git
  repo src/mirror-routing

  # Without the private repo, every repo uses the main identity.
  check $HOME/src/work user.email kalinduk.decosta@gmail.com
  check $HOME/src/work user.signingkey MAINKEY

  cat > $HOME/src/github.com/kalindudc/shell-private/git/gitconfig <<'CONFIG'
  [includeIf "hasconfig:remote.*.url:https://github.com/example-corp*/**"]
  	path = work.gitconfig
  [includeIf "gitdir:~/src/mirror-*/"]
  	path = work.gitconfig
  CONFIG
  printf '[user]\n\temail = jane@work.example\n\tsigningkey = WORKKEY\n' \
    > $HOME/src/github.com/kalindudc/shell-private/git/work.gitconfig

  check $HOME/src/mine user.email kalinduk.decosta@gmail.com
  check $HOME/src/mine user.signingkey MAINKEY
  check $HOME/src/work user.email jane@work.example
  check $HOME/src/work user.signingkey WORKKEY
  check $HOME/src/mirror-routing user.email jane@work.example

  # The public config holds no repo rules.
  if grep -q includeIf ${gitConfig}; then
    echo "the public git config must not contain includeIf rules" >&2
    exit 1
  fi
  touch $out
''
