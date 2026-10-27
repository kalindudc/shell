#!/usr/bin/env bash

# Applies the flake: nix-darwin on macOS, Home Manager on Linux. `task switch` and
# install.sh run this. On macOS the first argument picks the profile (personal or work).

set -euo pipefail

SHELL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"

# The profile the last switch applied, then work when Tec is installed, then personal.
darwin_profile() {
  if [[ -n "${1-}" ]]; then
    echo "$1"
  elif [[ -f /etc/shell-profile ]]; then
    cat /etc/shell-profile
  elif [[ -d "${HOME}/.local/state/tec" ]]; then
    echo work
  else
    echo personal
  fi
}

# Tec installs nix without the default profile, so use the nix-env next to the nix on PATH.
nix_env() {
  local dir
  dir="$(dirname "$(command -v nix)")"
  if [[ -x "${dir}/nix-env" ]]; then
    echo "${dir}/nix-env"
  else
    echo /nix/var/nix/profiles/default/bin/nix-env
  fi
}

"${SHELL_DIR}/src/scripts/unstow.sh"

case "$(uname -s)" in
  Darwin)
    profile="$(darwin_profile "${1-}")"
    echo "===> Building the ${profile} Mac configuration..."
    system="$(nix build --no-link --print-out-paths "${SHELL_DIR}#darwinConfigurations.${profile}.system")"
    echo "===> Activating ${system} (needs sudo)..."
    sudo -H "$(nix_env)" --profile /nix/var/nix/profiles/system --set "${system}"
    sudo -H "${system}/activate"
    ;;
  Linux)
    config="linux-$(uname -m)"
    echo "===> Applying the ${config} Home Manager configuration..."
    nix run "${SHELL_DIR}#home-manager" -- switch -b before-nix --flake "${SHELL_DIR}#${config}"
    ;;
  *)
    echo "Error: unsupported system $(uname -s)"
    exit 1
    ;;
esac
