#!/usr/bin/env bash

# Sets up a machine, and is safe to run again: installs Nix (and Homebrew on macOS),
# applies the flake (nix-darwin on macOS, Home Manager on Linux), then runs the setup
# steps that Nix does not manage (src/install.rb: tools, setup, bb, cortex).

set -euo pipefail

if [[ "${TRACE-0}" == "1" ]]; then
  set -x
fi

REPO_URL="https://github.com/kalindudc/shell.git"
REPO_DIR="${HOME}/src/github.com/kalindudc/shell"

usage() {
  cat <<'EOF'
Usage: ./install.sh [personal|work]

Installs Nix (and Homebrew on macOS), applies the flake with nix-darwin on macOS or
Home Manager on Linux, then runs src/install.rb (tools, setup, bb, cortex).

On macOS the profile defaults to work when Tec is installed, otherwise personal.
On Linux the profile argument is ignored.

Environment:
  TRACE=1             print every command
  SHELL_BRANCH=name   the branch the curl bootstrap clones (default: main)
  SHELL_SKIP_STEPS=1  apply the flake only, without src/install.rb
  SHELL_HEADLESS=1    on Linux, skip the desktop apps (server or container)
EOF
}

case "${1-}" in
  -h | --help)
    usage
    exit 0
    ;;
  "" | personal | work) ;;
  *)
    usage >&2
    exit 2
    ;;
esac

run_as_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

# Only git and curl are needed before Nix; the distribution installs the rest of its
# part in src/scripts/linux-system.sh.
install_linux_bootstrap() {
  local missing=()
  command -v git >/dev/null 2>&1 || missing+=(git)
  command -v curl >/dev/null 2>&1 || missing+=(curl)
  [[ ${#missing[@]} -eq 0 ]] && return 0

  echo "===> Installing ${missing[*]}..."
  if command -v apt-get >/dev/null 2>&1; then
    run_as_root apt-get update -qq
    run_as_root apt-get install -y "${missing[@]}"
  elif command -v pacman >/dev/null 2>&1; then
    run_as_root pacman -Sy --needed --noconfirm "${missing[@]}"
  else
    echo "Error: install ${missing[*]} with your package manager, then run ./install.sh again."
    exit 1
  fi
}

# git and the compilers come with the Xcode Command Line Tools.
ensure_xcode_tools() {
  xcode-select -p >/dev/null 2>&1 && return 0

  echo "===> Installing the Xcode Command Line Tools..."
  xcode-select --install || true
  echo "Finish the Command Line Tools installer, then run ./install.sh again."
  exit 1
}

if [[ "$(uname -s)" == "Darwin" ]]; then
  ensure_xcode_tools
else
  install_linux_bootstrap
fi

# bootstrap: `bash -c "$(curl ...)"` has no script file, so clone and run the checkout.
if [[ "${BASH_SOURCE[0]:-}" == "" ]] || [[ "${BASH_SOURCE[0]}" == "bash" ]]; then
  echo "===> Detected execution via curl, bootstrapping..."
  if [[ -d "${REPO_DIR}/.git" ]]; then
    echo "===> ${REPO_DIR} exists, updating..."
    git -C "${REPO_DIR}" pull --quiet
  elif [[ -e "${REPO_DIR}" ]]; then
    echo "Error: ${REPO_DIR} exists but is not a git repository"
    exit 1
  else
    echo "===> Cloning into ${REPO_DIR}..."
    mkdir -p "$(dirname "${REPO_DIR}")"
    git clone --recurse-submodules --branch "${SHELL_BRANCH:-main}" "${REPO_URL}" "${REPO_DIR}"
  fi
  exec bash "${REPO_DIR}/install.sh" "$@"
fi

SHELL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# The flake links $HOME to files in this checkout by absolute path (nix/home/dotfiles.nix).
if [[ "${SHELL_DIR}" != "$(cd "${REPO_DIR}" 2>/dev/null && pwd -P)" ]]; then
  echo "Error: the checkout must be at ${REPO_DIR}, not ${SHELL_DIR}."
  exit 1
fi

NOTICES_FILE="$(mktemp)"
export SHELL_NOTICES_FILE="${NOTICES_FILE}"
trap 'rm -f "${NOTICES_FILE}"' EXIT

git -C "${SHELL_DIR}" submodule update --init --quiet

if [[ "$(uname -s)" == "Linux" ]]; then
  "${SHELL_DIR}/src/scripts/linux-system.sh"
fi

ensure_nix() {
  if ! command -v nix >/dev/null 2>&1 &&
    [[ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
    # shellcheck disable=SC1091
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  fi
  command -v nix >/dev/null 2>&1 && return 0

  echo "===> Installing Nix (Determinate Systems installer)..."
  curl -fsSL https://install.determinate.systems/nix | sh -s -- install --no-confirm
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
}

ensure_homebrew() {
  [[ -x /opt/homebrew/bin/brew ]] && return 0

  echo "===> Installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}

ensure_nix

flake_user="$(nix eval --raw "${SHELL_DIR}#lib.user.username")"
if [[ "${flake_user}" != "$(id -un)" ]]; then
  echo "Error: the flake is for the user ${flake_user}, but you are $(id -un). Change nix/user.nix first."
  exit 1
fi

if [[ "$(uname -s)" == "Darwin" ]]; then
  ensure_homebrew
  "${SHELL_DIR}/src/scripts/switch.sh" "$@"
  export PATH="/etc/profiles/per-user/${USER}/bin:/run/current-system/sw/bin:${PATH}"
else
  "${SHELL_DIR}/src/scripts/switch.sh"
  export PATH="${HOME}/.nix-profile/bin:${XDG_STATE_HOME:-${HOME}/.local/state}/nix/profile/bin:${PATH}"
fi

if [[ "${SHELL_SKIP_STEPS-0}" != "1" ]]; then
  ruby "${SHELL_DIR}/src/install.rb"
fi

echo ""
echo "✓ Installation complete. Open a new terminal to load the new shell."
if [[ -s "${NOTICES_FILE}" ]]; then
  echo ""
  echo "! Log out and back in to finish:"
  sed 's/^/  - /' "${NOTICES_FILE}"
fi
