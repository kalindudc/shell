#!/usr/bin/env bash

# Shell Dotfiles Installation Bootstrap
# Minimal bash bootstrap that installs git + ruby, then hands off to Ruby orchestrator

set -euo pipefail

# Enable debug mode if TRACE is set
if [[ "${TRACE-0}" == "1" ]]; then
  set -x
fi

# Install git if missing
if ! command -v git >/dev/null 2>&1; then
  echo "===> Installing git..."
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -qq && sudo apt-get install -y git
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -Sy --noconfirm git
  elif command -v brew >/dev/null 2>&1; then
    brew install git
  else
    echo "Error: Unable to install git. Please install git manually."
    exit 1
  fi
fi

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

# Install ruby if missing
if ! command -v ruby >/dev/null 2>&1; then
  echo "===> Installing ruby..."
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -qq && sudo apt-get install -y ruby
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -Sy --noconfirm ruby
  elif command -v brew >/dev/null 2>&1; then
    brew install ruby
  else
    echo "Error: Unable to install ruby. Please install ruby manually."
    exit 1
  fi
fi

# Execute Ruby orchestrator
exec ruby "${SHELL_DIR}/src/install.rb" "$@"
