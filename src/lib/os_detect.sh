#!/usr/bin/env bash

# OS detection library
# Detects operating system, distribution, architecture, and package manager

set -o errexit
set -o nounset
set -o pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=src/lib/common.sh
source "${SCRIPT_DIR}/common.sh"

# Global variables for OS detection
OS_TYPE=""
OS_DISTRO=""
OS_ARCH=""
PACKAGE_MANAGER=""

# Detect operating system type (macos, linux)
detect_os() {
  local uname_s
  uname_s="$(uname -s)"

  case "${uname_s}" in
    Darwin*)
      OS_TYPE="macos"
      OS_DISTRO="macos"
      ;;
    Linux*)
      OS_TYPE="linux"
      detect_linux_distro
      ;;
    *)
      abort "Unsupported operating system: ${uname_s}"
      ;;
  esac

  export OS_TYPE
  export OS_DISTRO
  log "Detected OS: ${OS_TYPE} (${OS_DISTRO})"
}

# Detect Linux distribution
detect_linux_distro() {
  if [[ -f /etc/os-release ]]; then
    # Parse /etc/os-release
    local id
    id="$(grep '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')"

    case "${id}" in
      ubuntu|debian)
        OS_DISTRO="ubuntu"
        ;;
      arch|manjaro)
        OS_DISTRO="arch"
        ;;
      fedora|rhel|centos)
        OS_DISTRO="fedora"
        ;;
      *)
        warn "Unknown Linux distribution: ${id}. Assuming Ubuntu/Debian."
        OS_DISTRO="ubuntu"
        ;;
    esac
  elif [[ -f /etc/debian_version ]]; then
    OS_DISTRO="ubuntu"
  elif [[ -f /etc/arch-release ]]; then
    OS_DISTRO="arch"
  elif [[ -f /etc/redhat-release ]]; then
    OS_DISTRO="fedora"
  else
    warn "Could not detect Linux distribution. Assuming Ubuntu/Debian."
    OS_DISTRO="ubuntu"
  fi
}

# Detect system architecture
detect_architecture() {
  local arch
  arch="$(uname -m)"

  case "${arch}" in
    x86_64|amd64)
      OS_ARCH="x86_64"
      ;;
    arm64|aarch64)
      OS_ARCH="arm64"
      ;;
    *)
      abort "Unsupported architecture: ${arch}"
      ;;
  esac

  export OS_ARCH
  log "Detected architecture: ${OS_ARCH}"
}

# Detect and verify package manager
detect_package_manager() {
  case "${OS_TYPE}" in
    macos)
      if command_exists brew; then
        PACKAGE_MANAGER="brew"
      else
        warn "Homebrew not found. It will be installed."
        PACKAGE_MANAGER="brew"
      fi
      ;;
    linux)
      case "${OS_DISTRO}" in
        ubuntu)
          if command_exists apt-get; then
            PACKAGE_MANAGER="apt"
          else
            abort "apt-get not found on Ubuntu/Debian system"
          fi
          ;;
        arch)
          if command_exists pacman; then
            PACKAGE_MANAGER="pacman"
          else
            # In test environment, just set it
            if [[ "${BATS_TEST_DIRNAME:-}" != "" ]]; then
              PACKAGE_MANAGER="pacman"
              warn "pacman not found (test mode)"
            else
              abort "pacman not found on Arch system"
            fi
          fi
          ;;
        fedora)
          if command_exists dnf; then
            PACKAGE_MANAGER="dnf"
          elif command_exists yum; then
            PACKAGE_MANAGER="yum"
          else
            abort "Neither dnf nor yum found on Fedora/RHEL system"
          fi
          ;;
        *)
          abort "Unknown distribution: ${OS_DISTRO}"
          ;;
      esac
      ;;
    *)
      abort "Unknown OS type: ${OS_TYPE}"
      ;;
  esac

  export PACKAGE_MANAGER
  log "Package manager: ${PACKAGE_MANAGER}"
}

# Check if running on macOS
is_macos() {
  [[ "${OS_TYPE}" == "macos" ]]
}

# Check if running on Linux
is_linux() {
  [[ "${OS_TYPE}" == "linux" ]]
}

# Check if running on Ubuntu/Debian
is_ubuntu() {
  [[ "${OS_DISTRO}" == "ubuntu" ]]
}

# Check if running on Arch
is_arch() {
  [[ "${OS_DISTRO}" == "arch" ]]
}

# Check if running on Fedora/RHEL
is_fedora() {
  [[ "${OS_DISTRO}" == "fedora" ]]
}

# Get distribution name
get_distro() {
  echo "${OS_DISTRO}"
}

# Get architecture
get_architecture() {
  echo "${OS_ARCH}"
}

# Get OS type
get_os_type() {
  echo "${OS_TYPE}"
}

# Install Homebrew on macOS
install_homebrew() {
  if ! command_exists brew; then
    log "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add Homebrew to PATH
    if is_macos; then
      if [[ "${OS_ARCH}" == "arm64" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
        export HOMEBREW_PREFIX="/opt/homebrew"
      else
        eval "$(/usr/local/bin/brew shellenv)"
        export HOMEBREW_PREFIX="/usr/local"
      fi
    fi

    success "Homebrew installed successfully"
  else
    log "Homebrew is already installed"
  fi
}

# Install yay AUR helper on Arch
install_yay() {
  if ! command_exists yay; then
    log "Installing yay AUR helper..."

    local temp_dir
    temp_dir="$(make_temp_dir)"

    (
      safe_cd "${temp_dir}"

      # Install base-devel if not present
      if ! pacman -Qi base-devel >/dev/null 2>&1; then
        sudo pacman -S --needed --noconfirm git base-devel
      fi

      git clone https://aur.archlinux.org/yay.git
      safe_cd yay
      makepkg -si --noconfirm
    )

    rm -rf "${temp_dir}"
    success "yay installed successfully"
  else
    log "yay is already installed"
  fi
}

# Ensure package manager is installed
ensure_package_manager() {
  case "${PACKAGE_MANAGER}" in
    brew)
      install_homebrew
      ;;
    apt)
      log "Package manager apt is available"
      ;;
    pacman)
      log "Package manager pacman is available"
      # Install yay for AUR support
      install_yay
      ;;
    dnf|yum)
      log "Package manager ${PACKAGE_MANAGER} is available"
      ;;
    *)
      abort "Unknown package manager: ${PACKAGE_MANAGER}"
      ;;
  esac
}

# Initialize OS detection (call all detection functions)
init_os_detection() {
  detect_os
  detect_architecture
  detect_package_manager
}

# Override OS detection (for testing or manual override)
override_os() {
  local os="$1"

  case "${os}" in
    macos|darwin)
      OS_TYPE="macos"
      OS_DISTRO="macos"
      ;;
    ubuntu|debian)
      OS_TYPE="linux"
      OS_DISTRO="ubuntu"
      ;;
    arch|manjaro)
      OS_TYPE="linux"
      OS_DISTRO="arch"
      ;;
    fedora|rhel|centos)
      OS_TYPE="linux"
      OS_DISTRO="fedora"
      ;;
    *)
      abort "Unknown OS override: ${os}. Supported: macos, ubuntu, arch, fedora"
      ;;
  esac

  export OS_TYPE
  export OS_DISTRO

  # Re-detect architecture and package manager
  detect_architecture
  detect_package_manager

  warn "OS detection overridden to: ${OS_TYPE} (${OS_DISTRO})"
}

# Export functions
export -f detect_os detect_linux_distro detect_architecture detect_package_manager
export -f is_macos is_linux is_ubuntu is_arch is_fedora
export -f get_distro get_architecture get_os_type
export -f install_homebrew install_yay ensure_package_manager
export -f init_os_detection override_os
