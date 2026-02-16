#!/usr/bin/env bash

# Package management library
# Provides cross-platform package installation with category-based organization

set -o errexit
set -o nounset
set -o pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=src/lib/common.sh
source "${SCRIPT_DIR}/common.sh"
# shellcheck source=src/lib/os_detect.sh
source "${SCRIPT_DIR}/os_detect.sh"

# Package categories (core packages must be installed first for templating)
readonly PACKAGES_CORE=(
  "git"
  "curl"
  "wget"
  "stow"
  "ruby"
  "gpg"
)

readonly PACKAGES_SHELL=(
  "zsh"
  "fzf"
  "ripgrep"
  "zoxide"
  "fd"
  "direnv"
)

readonly PACKAGES_DEV=(
  "neovim"
  "gh"
  "gcc"
  "go-task"
  "git-delta"
  "jq"
)

readonly PACKAGES_RUNTIMES=(
  "go"
)

readonly PACKAGES_DEVOPS=(
  "kubectl"
  "helm"
  "docker"
  "docker-compose"
)

readonly PACKAGES_FONTS=(
  "nerd-fonts"
)

readonly PACKAGES_OPTIONAL=(
  "1password-cli"
  "lazygit"
  "vscode"
  "ghostty"
)

# Map generic package name to OS-specific name
# Usage: map_package_name "generic-name"
map_package_name() {
  local package="$1"
  local mapped_name="${package}"

  case "${OS_DISTRO}" in
    ubuntu)
      case "${package}" in
        fd) mapped_name="fd-find" ;;
        ripgrep) mapped_name="ripgrep" ;;
        gpg) mapped_name="gnupg" ;;
        go-task) mapped_name="" ;;  # Installed via snap
        git-delta) mapped_name="" ;;  # Custom install
        nerd-fonts) mapped_name="" ;;  # Not in apt
        1password-cli) mapped_name="" ;;  # Not in apt
        lazygit) mapped_name="" ;;  # Not in apt
        vscode) mapped_name="" ;;  # Installed via snap
        ghostty) mapped_name="" ;;  # Installed via snap
        zoxide) mapped_name="" ;;  # Custom install
        docker) mapped_name="docker.io" ;;
        docker-compose) mapped_name="docker-compose" ;;
      esac
      ;;
    arch)
      case "${package}" in
        gpg) mapped_name="gnupg" ;;
        gh) mapped_name="github-cli" ;;
        ripgrep) mapped_name="ripgrep" ;;
        go-task) mapped_name="" ;;  # Installed from AUR
        git-delta) mapped_name="" ;;  # Installed from AUR
        nerd-fonts) mapped_name="" ;;  # Installed from AUR
        vscode) mapped_name="" ;;  # Installed from AUR
        ghostty) mapped_name="" ;;  # Installed from AUR
        zoxide) mapped_name="" ;;  # Installed from AUR
        docker-compose) mapped_name="" ;;  # Installed from AUR
      esac
      ;;
    macos)
      case "${package}" in
        gpg) mapped_name="gnupg" ;;
        go-task) mapped_name="go-task" ;;
        vscode) mapped_name="visual-studio-code" ;;
        nerd-fonts) mapped_name="" ;;  # Special handling
        ghostty) mapped_name="" ;;  # Not available
        docker-compose) mapped_name="" ;;  # Part of Docker Desktop
      esac
      ;;
  esac

  echo "${mapped_name}"
}

# Check if package is installed
# Usage: is_package_installed "package-name"
is_package_installed() {
  local package="$1"

  case "${PACKAGE_MANAGER}" in
    brew)
      brew list "${package}" >/dev/null 2>&1
      ;;
    apt)
      # dpkg -l returns 0 even for uninstalled packages, so we must check output
      # Status should be 'ii' (installed) at the start of the line
      dpkg -l "${package}" 2>/dev/null | grep -q "^ii  ${package}"
      ;;
    pacman)
      pacman -Qi "${package}" >/dev/null 2>&1
      ;;
    *)
      command_exists "${package}"
      ;;
  esac
}

# Install a single package
# Usage: install_package "package-name"
install_package() {
  local package="$1"
  local mapped_name
  mapped_name="$(map_package_name "${package}")"

  # Skip if empty (needs custom install)
  if [[ -z "${mapped_name}" ]]; then
    return 0
  fi

  # Check if already installed
  if is_package_installed "${mapped_name}"; then
    log "${package} is already installed"
    return 0
  fi

  log "Installing ${package}..."

  case "${PACKAGE_MANAGER}" in
    brew)
      brew install "${mapped_name}"
      ;;
    apt)
      maybe_sudo apt-get install -y "${mapped_name}"
      ;;
    pacman)
      maybe_sudo pacman -S --needed --noconfirm "${mapped_name}"
      ;;
    *)
      abort "Unknown package manager: ${PACKAGE_MANAGER}"
      ;;
  esac

  # Verify installation succeeded
  if is_package_installed "${mapped_name}"; then
    success "Installed ${package}"
  else
    error "Failed to install ${package} (${mapped_name})"
    error "Please install it manually and re-run the installation"
    return 1
  fi
}

# Update PATH to include common binary locations
# Call this after installing packages to ensure they're available in current session
update_path() {
  local common_paths=(
    "/usr/local/bin"
    "/usr/bin"
    "/bin"
    "/usr/local/sbin"
    "/usr/sbin"
    "/sbin"
    "${HOME}/.local/bin"
    "/opt/homebrew/bin"  # Apple Silicon Homebrew
    "/usr/local/opt"     # Intel Mac Homebrew
  )

  for dir in "${common_paths[@]}"; do
    if [[ -d "${dir}" ]] && [[ ":${PATH}:" != *":${dir}:"* ]]; then
      export PATH="${dir}:${PATH}"
    fi
  done
  
  # Hash -r to refresh bash's command cache
  hash -r 2>/dev/null || true
}

# Install a list of packages
# Usage: install_package_list package1 package2 package3...
install_package_list() {
  local packages=("$@")

  for package in "${packages[@]}"; do
    install_package "${package}"
  done
}

# Install core packages (git, curl, stow, ruby)
install_packages_core() {
  log "Installing core packages..."

  case "${PACKAGE_MANAGER}" in
    brew)
      brew update
      brew upgrade
      ;;
    apt)
      maybe_sudo apt-get update
      maybe_sudo apt-get upgrade -y
      ;;
    pacman)
      maybe_sudo pacman -Syu --noconfirm
      ;;
  esac

  install_package_list "${PACKAGES_CORE[@]}"

  # Update PATH to ensure newly installed CORE packages are available
  # This is called ONCE because only CORE packages are needed for the installation to function
  # (stow for dotfiles, ruby for templating, git for cloning, etc.)
  # Other packages (shell, dev, devops) are installed but not required for this script to work
  update_path

  # Install ruby gems for templating
  if command_exists gem; then
    log "Installing Ruby ERB (required for templating)..."
    gem install erb || true
  fi

  success "Core packages installed"
}

# Install shell packages
install_packages_shell() {
  log "Installing shell packages..."
  install_package_list "${PACKAGES_SHELL[@]}"

  # Install starship
  install_starship

  # Install zoxide (custom install for Ubuntu)
  if is_ubuntu && ! command_exists zoxide; then
    log "Installing zoxide..."
    curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
  elif is_arch && ! command_exists zoxide; then
    log "Installing zoxide from AUR..."
    yay -S --needed --noconfirm zoxide
  fi

  success "Shell packages installed"
}

# Install development packages
install_packages_dev() {
  log "Installing development packages..."
  install_package_list "${PACKAGES_DEV[@]}"

  # Install git-delta (custom install for Ubuntu)
  if is_ubuntu && ! command_exists delta; then
    log "Installing git-delta..."
    local delta_url
    delta_url="$(curl -s https://api.github.com/repos/dandavison/delta/releases/latest \
      | grep 'browser_download_url.*amd64.*\.deb' \
      | cut -d'"' -f4)"

    if [[ -n "${delta_url}" ]]; then
      local tmp_dir="${INSTALL_SCRIPT_DIR:-${HOME}}/tmp"
      mkdir -p "${tmp_dir}"
      wget -O "${tmp_dir}/git-delta.deb" "${delta_url}"
      maybe_sudo dpkg -i "${tmp_dir}/git-delta.deb"
      rm "${tmp_dir}/git-delta.deb"
    fi
  elif is_arch && ! command_exists delta; then
    yay -S --needed --noconfirm git-delta
  fi

  # Install go-task (snap for Ubuntu, AUR for Arch)
  if is_ubuntu && ! command_exists task; then
    maybe_sudo snap install task --classic
  elif is_arch && ! command_exists task; then
    yay -S --needed --noconfirm go-task-bin
  fi

  success "Development packages installed"
}

# Install runtime packages
install_packages_runtimes() {
  log "Installing runtime packages..."
  install_package_list "${PACKAGES_RUNTIMES[@]}"

  # Install pyenv
  install_pyenv

  # Install nvm
  install_nvm

  success "Runtime packages installed"
}

# Install DevOps packages
install_packages_devops() {
  log "Installing DevOps packages..."

  # Install kubectl and helm
  case "${PACKAGE_MANAGER}" in
    brew)
      brew install kubectl helm
      ;;
    apt)
      maybe_sudo snap install kubectl --classic
      maybe_sudo snap install helm --classic
      ;;
    pacman)
      yay -S --needed --noconfirm kubectl helm
      ;;
  esac

  # Install Docker
  install_docker

  success "DevOps packages installed"
}

# Install Docker and docker-compose
install_docker() {
  # Check for docker and docker compose (v2 uses 'docker compose', v1 uses 'docker-compose')
  if command_exists docker && (docker compose version >/dev/null 2>&1 || command_exists docker-compose); then
    log "Docker and docker compose are already installed"
    return 0
  fi

  log "Installing Docker..."

  case "${OS_DISTRO}" in
    macos)
      # Docker Desktop for Mac
      if ! command_exists docker; then
        brew install --cask docker
        success "Docker Desktop installed. Please start Docker Desktop from Applications."
      fi
      ;;

    ubuntu)
      # Install docker.io and docker-compose-plugin from apt
      if ! command_exists docker; then
        maybe_sudo apt-get install -y docker.io
        maybe_sudo systemctl enable docker
        maybe_sudo systemctl start docker

        # Add current user to docker group (if USER is set and not root)
        if [[ -n "${USER:-}" ]] && [[ "${USER}" != "root" ]]; then
          maybe_sudo usermod -aG docker "${USER}"
          warn "You may need to log out and back in for docker group membership to take effect"
        fi
      fi

      # Install docker compose (v2 plugin or v1 standalone)
      if ! docker compose version >/dev/null 2>&1 && ! command_exists docker-compose; then
        maybe_sudo apt-get install -y docker-compose-plugin || maybe_sudo apt-get install -y docker-compose
      fi
      ;;

    arch)
      # Install docker and docker-compose
      if ! command_exists docker; then
        maybe_sudo pacman -S --needed --noconfirm docker
        maybe_sudo systemctl enable docker
        maybe_sudo systemctl start docker

        # Add current user to docker group (if USER is set and not root)
        if [[ -n "${USER:-}" ]] && [[ "${USER}" != "root" ]]; then
          maybe_sudo usermod -aG docker "${USER}"
          warn "You may need to log out and back in for docker group membership to take effect"
        fi
      fi

      if ! command_exists docker-compose; then
        yay -S --needed --noconfirm docker-compose
      fi
      ;;
  esac

  success "Docker installed"
}

# Install fonts
install_packages_fonts() {
  log "Installing Nerd Fonts..."

  case "${OS_DISTRO}" in
    macos)
      # Install all nerd fonts
      brew search '/font-.*-nerd-font/' | awk '{ print $1 }' | xargs -I{} brew install --cask {} || true
      ;;
    arch)
      if prompt_for_yn "Install Nerd Fonts? (y/N)" "N"; then
        yay -S --needed --noconfirm \
          ttf-hack-nerd \
          ttf-firacode-nerd \
          ttf-jetbrains-mono-nerd \
          ttf-meslo-nerd \
          ttf-sourcecodepro-nerd
      fi
      ;;
    ubuntu)
      warn "Nerd Fonts must be installed manually on Ubuntu"
      ;;
  esac

  success "Fonts installation complete"
}

# Install optional packages
install_packages_optional() {
  log "Installing optional packages..."

  # Visual Studio Code
  if is_ubuntu; then
    maybe_sudo snap install code --classic
  elif is_arch; then
    yay -S --needed --noconfirm visual-studio-code-bin
  elif is_macos; then
    brew install --cask visual-studio-code
  fi

  # Ghostty
  if is_ubuntu; then
    maybe_sudo snap install ghostty --classic || warn "Ghostty not available"
  elif is_arch; then
    yay -S --needed --noconfirm ghostty || warn "Ghostty not available"
  fi

  # 1Password CLI (macOS only)
  if is_macos; then
    brew install 1password-cli
  fi

  # Lazygit
  if is_macos; then
    brew install jesseduffield/lazygit/lazygit
  fi

  success "Optional packages installed"
}

# Install starship prompt
install_starship() {
  if command_exists starship; then
    log "Starship is already installed"
    return 0
  fi

  log "Installing Starship prompt..."

  if is_arch; then
    yay -S --needed --noconfirm starship
  else
    curl -sS https://starship.rs/install.sh | sh -s -- -y
  fi

  success "Starship installed"
}

# Install NVM (Node Version Manager)
install_nvm() {
  if [[ -d "${HOME}/.nvm" ]]; then
    log "NVM is already installed"
    return 0
  fi

  log "Installing NVM..."

  if is_arch; then
    yay -S --needed --noconfirm nvm
  else
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash
  fi

  success "NVM installed"
}

# Install pyenv (Python version manager)
install_pyenv() {
  if command_exists pyenv; then
    log "pyenv is already installed"
    return 0
  fi

  log "Installing pyenv..."

  # Install dependencies first
  case "${OS_DISTRO}" in
    ubuntu)
      maybe_sudo apt-get install -y \
        build-essential libssl-dev zlib1g-dev \
        libbz2-dev libreadline-dev libsqlite3-dev \
        libncursesw5-dev xz-utils tk-dev \
        libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev
      ;;
    arch)
      maybe_sudo pacman -S --needed --noconfirm \
        base-devel openssl zlib xz tk
      ;;
  esac

  curl https://pyenv.run | bash

  success "pyenv installed"
}

# Install oh-my-zsh
install_ohmyzsh() {
  if [[ -d "${HOME}/.oh-my-zsh" ]]; then
    log "oh-my-zsh is already installed"
    return 0
  fi

  log "Installing oh-my-zsh..."

  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

  success "oh-my-zsh installed"
}

# Install pipx and packages
install_pipx_packages() {
  if ! command_exists pipx; then
    log "Installing pipx..."

    case "${PACKAGE_MANAGER}" in
      brew)
        brew install pipx
        ;;
      apt)
        maybe_sudo apt-get install -y pipx
        ;;
      pacman)
        maybe_sudo pacman -S --needed --noconfirm python-pipx
        ;;
    esac
  fi

  log "Installing pipx packages..."
  pipx install dunk || true

  success "pipx packages installed"
}

# Export functions
export -f map_package_name is_package_installed update_path
export -f install_package install_package_list
export -f install_packages_core install_packages_shell
export -f install_packages_dev install_packages_runtimes
export -f install_packages_devops install_packages_fonts
export -f install_packages_optional
export -f install_starship install_nvm install_pyenv
export -f install_ohmyzsh install_pipx_packages
export -f install_docker
