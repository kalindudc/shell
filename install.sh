#!/usr/bin/env bash

# Shell Dotfiles Installation Bootstrap
# Minimal bash bootstrap that installs git + ruby, then hands off to Ruby orchestrator

set -euo pipefail

# Enable debug mode if TRACE is set
if [[ "${TRACE-0}" == "1" ]]; then
  set -x
fi

run_as_root() {
  local manual_command="$1"
  shift

  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    echo "Error: sudo is required to install dependencies automatically."
    echo "Install sudo or run this command as root, then retry: ${manual_command}"
    exit 1
  fi
}

install_bootstrap_package() {
  local package="$1"

  if command -v "${package}" >/dev/null 2>&1; then
    return 0
  fi

  echo "===> Installing ${package}..."
  if command -v apt-get >/dev/null 2>&1; then
    run_as_root "apt-get update && apt-get install -y ${package}" apt-get update -qq
    run_as_root "apt-get install -y ${package}" apt-get install -y "${package}"
  elif command -v pacman >/dev/null 2>&1; then
    run_as_root "pacman -Sy --noconfirm ${package}" pacman -Sy --noconfirm "${package}"
  elif command -v brew >/dev/null 2>&1; then
    brew install "${package}"
  else
    echo "Error: Unable to install ${package}; no supported package manager was found."
    echo "Install one of apt-get, pacman, or Homebrew, then run: ./install.sh"
    exit 1
  fi
}

install_bootstrap_package git

# bootstrap

if [[ "${BASH_SOURCE[0]:-}" == "" ]] || [[ "${BASH_SOURCE[0]}" == "bash" ]]; then
  echo "===> Detected execution via curl, bootstrapping..."

  BOOTSTRAP_CLONE_DIR="${SHELL_INSTALL_DIR:-${HOME}/src/github.com/kalindudc}"
  BOOTSTRAP_SHELL_DIR="${BOOTSTRAP_CLONE_DIR}/shell"

  echo "===> Repository will be cloned to: ${BOOTSTRAP_SHELL_DIR}"

  # Check if directory already exists
  if [[ -d "${BOOTSTRAP_SHELL_DIR}" ]]; then
    echo "===> Directory already exists, updating..."
    cd "${BOOTSTRAP_SHELL_DIR}"
    if [[ -d .git ]]; then
      git pull --quiet
    else
      echo "Error: ${BOOTSTRAP_SHELL_DIR} exists but is not a git repository"
      exit 1
    fi
  else
    echo "===> Cloning repository..."
    mkdir -p "${BOOTSTRAP_CLONE_DIR}"
    git clone --depth 1 https://github.com/kalindudc/shell.git "${BOOTSTRAP_SHELL_DIR}"
  fi

  echo "===> Re-executing from cloned repository..."
  cd "${BOOTSTRAP_SHELL_DIR}"
  exec bash "${BOOTSTRAP_SHELL_DIR}/install.sh" "$@"

  echo "Error: Failed to execute cloned script"
  exit 1
fi

# main

SHELL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure ruby is available using the detected platform package manager.
# Do not use Bundler for installer runtime; Gemfile remains dev/test-only.
# If sudo/package manager is unavailable, install_bootstrap_package prints the exact next step.
install_bootstrap_package ruby

# Execute Ruby orchestrator
exec ruby "${SHELL_DIR}/src/install.rb" "$@"
