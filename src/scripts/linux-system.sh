#!/usr/bin/env bash

# The parts of a Linux machine that Home Manager cannot manage: zsh as the login shell,
# Docker and its group, build tools for pyenv, FUSE for the bb AppImage, and the desktop
# apps. Runs on Arch, and on Ubuntu, Debian and their derivatives. Needs sudo.
# SHELL_HEADLESS=1 skips the desktop apps, for a server or a container.

set -euo pipefail

HEADLESS="${SHELL_HEADLESS-0}"

ARCH_PACKAGES=(base-devel curl docker docker-compose fuse2 git zsh)
ARCH_DESKTOP_PACKAGES=(flatpak ghostty)
# The -dev packages let pyenv build Python.
DEBIAN_PACKAGES=(
  build-essential curl docker.io git zsh
  libbz2-dev libffi-dev liblzma-dev libncursesw5-dev libreadline-dev libsqlite3-dev
  libssl-dev libxml2-dev libxmlsec1-dev tk-dev xz-utils zlib1g-dev
)
FLATPAKS=(com.google.Chrome com.discordapp.Discord com.spotify.Client)

warn() { printf '! %s\n' "$*"; }
notice() { printf '%s\n' "$*" >>"${SHELL_NOTICES_FILE:-/dev/stderr}"; }

as_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

install_arch() {
  as_root pacman -Syu --needed --noconfirm "${ARCH_PACKAGES[@]}"
  [[ "${HEADLESS}" == "1" ]] && return
  as_root pacman -S --needed --noconfirm "${ARCH_DESKTOP_PACKAGES[@]}"
  if command -v yay >/dev/null 2>&1; then
    yay -S --needed --noconfirm visual-studio-code-bin
  else
    warn "yay not found, skipping VS Code"
  fi
}

# Keep config files that already exist, such as the /etc/zsh/zshrc that the Nix installer
# edits, instead of stopping at dpkg's question.
apt_install() {
  as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold "$@"
}

install_debian() {
  as_root apt-get update
  apt_install "${DEBIAN_PACKAGES[@]}"
  # AppImages mount themselves with FUSE 2; Ubuntu 24.04 renamed its package to libfuse2t64.
  if apt-cache show libfuse2t64 >/dev/null 2>&1; then
    apt_install libfuse2t64
  else
    apt_install libfuse2
  fi
  [[ "${HEADLESS}" == "1" ]] && return
  apt_install flatpak
  if command -v snap >/dev/null 2>&1; then
    as_root snap install code --classic
    as_root snap install ghostty --classic
  else
    warn "snap not found, skipping VS Code and Ghostty"
  fi
}

install_flatpaks() {
  [[ "${HEADLESS}" == "1" ]] && return
  if ! command -v flatpak >/dev/null 2>&1; then
    warn "flatpak not found, skipping ${FLATPAKS[*]}"
    return
  fi
  as_root flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  local app
  for app in "${FLATPAKS[@]}"; do
    as_root flatpak install -y --noninteractive flathub "${app}" || warn "flatpak install ${app} failed"
  done
}

setup_docker() {
  if [[ -d /run/systemd/system ]]; then
    as_root systemctl enable --now docker || warn "could not start docker"
  fi
  [[ "${EUID}" -eq 0 ]] && return
  if ! id -nG "${USER}" | tr ' ' '\n' | grep -qx docker; then
    as_root usermod -aG docker "${USER}"
    notice "Docker group membership needs a new login session"
  fi
}

# The distribution's zsh is the login shell; Home Manager writes ~/.zshrc.
set_login_shell() {
  local zsh current
  zsh="$(command -v zsh)"
  current="$(getent passwd "${USER:-$(id -un)}" | cut -d: -f7)"
  [[ "${current}" == */zsh ]] && return
  grep -qx "${zsh}" /etc/shells || echo "${zsh}" | as_root tee -a /etc/shells >/dev/null
  as_root chsh -s "${zsh}" "${USER:-$(id -un)}"
  notice "The default shell change to zsh needs a new login session"
}

if command -v pacman >/dev/null 2>&1; then
  install_arch
elif command -v apt-get >/dev/null 2>&1; then
  install_debian
else
  echo "Error: no pacman or apt-get found; this script supports Arch, Ubuntu and Debian."
  exit 1
fi

install_flatpaks
setup_docker
set_login_shell
