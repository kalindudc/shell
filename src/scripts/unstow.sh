#!/usr/bin/env bash

# Moves a machine off the old stow layout, once: removes the links stow made into the
# checkout's home/ so Home Manager can link the same paths. Safe to run again; Home
# Manager's own links point into the Nix store and are left alone.
#
# stow linked ~/.gitconfig to a generated file in the checkout. Its generated part is
# now ~/.config/git/config, so only what tools added after it moves to the writable
# ~/.gitconfig, and its signing key moves to ~/.config/git/signing. The whole file is
# kept as ~/.gitconfig.before-nix.

set -euo pipefail

SHELL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
HOME_DIR="${SHELL_DIR}/home"
# stow writes relative links, so match the checkout's path below $HOME.
STOW_PATH="${HOME_DIR#"${HOME}"/}/"

stow_link() {
  [[ -L "$1" ]] && [[ "$(readlink "$1")" == *"${STOW_PATH}"* ]]
}

migrate_gitconfig() {
  local old="${HOME}/.gitconfig" backup="${HOME}/.gitconfig.before-nix" key
  stow_link "${old}" || return 0

  if [[ -f "${old}" ]]; then
    cp -L "${old}" "${backup}"
    key="$(git config --file "${backup}" user.signingkey || true)"
    if [[ -n "${key}" ]]; then
      mkdir -p "${HOME}/.config/git"
      git config --file "${HOME}/.config/git/signing" user.signingkey "${key}"
      git config --file "${HOME}/.config/git/signing" commit.gpgsign true
    fi
  fi
  rm "${old}"

  if [[ -f "${backup}" ]]; then
    # The generated part ended with the include of the private repo's git config.
    awk 'done { print } /shell-private\/git\/gitconfig/ { done = 1 }' "${backup}" >"${old}"
    echo "===> Kept what tools added to ~/.gitconfig; the old file is ${backup}"
  fi
}

links=()
while IFS= read -r -d '' link; do
  stow_link "${link}" && links+=("${link}")
done < <(find "${HOME}" -maxdepth 4 \
  \( -path "${HOME}/Library" -o -path "${HOME}/src" -o -path "${HOME}/.cache" \
  -o -path "${HOME}/.local/share" -o -path "${HOME}/.Trash" -o -path "${HOME}/go" \
  -o -path "${HOME}/.npm" -o -path "${HOME}/.nix-profile" -o -name node_modules \) -prune \
  -o -type l -print0 2>/dev/null)

[[ ${#links[@]} -eq 0 ]] && exit 0

echo "===> Removing ${#links[@]} stow links into ${HOME_DIR}..."
migrate_gitconfig
for link in "${links[@]}"; do
  [[ "${link}" == "${HOME}/.gitconfig" ]] && continue
  rm "${link}"
done
