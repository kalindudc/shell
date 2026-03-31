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

# Minimum fzf version required for interactive features (--no-input, hide-input, $FZF_INPUT_STATE).
readonly FZF_MIN_VERSION="0.59.0"

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
        fzf) mapped_name="" ;;  # apt version is too old; custom install from GitHub releases
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

  # install NVM for ubuntu / macos
  if is_ubuntu || is_macos; then
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  fi

  success "Core packages installed"
}

# Compare two semver strings. Returns 0 if $1 >= $2, 1 otherwise.
version_gte() {
  local have="$1" need="$2"
  # printf ensures consistent zero-padded comparison
  printf '%s\n%s\n' "${need}" "${have}" | sort -V | head -n1 | grep -qx "${need}"
}

# Ensure fzf is installed and meets the minimum version requirement.
# On Ubuntu the apt package is typically too old, so we install from GitHub releases.
# On other platforms the package manager version is usually sufficient.
install_fzf() {
  if command_exists fzf; then
    local current_version
    current_version="$(fzf --version 2>/dev/null | awk '{print $1}')"
    if version_gte "${current_version}" "${FZF_MIN_VERSION}"; then
      log "fzf ${current_version} is already installed (>= ${FZF_MIN_VERSION})"
      return 0
    fi
    warn "fzf ${current_version} is installed but < ${FZF_MIN_VERSION}; upgrading..."
  fi

  log "Installing fzf >= ${FZF_MIN_VERSION}..."

  case "${OS_DISTRO}" in
    macos)
      brew install fzf
      ;;
    arch)
      maybe_sudo pacman -S --needed --noconfirm fzf
      ;;
    ubuntu)
      # apt fzf is too old on most Ubuntu releases; install from GitHub.
      local arch_suffix
      case "$(uname -m)" in
        x86_64)  arch_suffix="linux_amd64" ;;
        aarch64) arch_suffix="linux_arm64" ;;
        armv7l)  arch_suffix="linux_armv7" ;;
        *)       abort "Unsupported architecture: $(uname -m)" ;;
      esac

      local fzf_url
      fzf_url="$(curl -s https://api.github.com/repos/junegunn/fzf/releases/latest \
        | grep "browser_download_url.*${arch_suffix}.tar.gz" \
        | cut -d'"' -f4)"

      if [[ -z "${fzf_url}" ]]; then
        abort "Could not determine fzf download URL"
      fi

      local tmp_dir
      tmp_dir="$(mktemp -d)"
      curl -fsSL "${fzf_url}" | tar xz -C "${tmp_dir}"
      maybe_sudo install -m 755 "${tmp_dir}/fzf" /usr/local/bin/fzf
      rm -rf "${tmp_dir}"
      ;;
    *)
      abort "Unsupported OS for fzf installation: ${OS_DISTRO}"
      ;;
  esac

  # Verify
  if command_exists fzf; then
    local installed_version
    installed_version="$(fzf --version 2>/dev/null | awk '{print $1}')"
    if version_gte "${installed_version}" "${FZF_MIN_VERSION}"; then
      success "fzf ${installed_version} installed"
    else
      error "fzf ${installed_version} installed but still < ${FZF_MIN_VERSION}"
      return 1
    fi
  else
    error "fzf installation failed"
    return 1
  fi
}

# Install shell packages
install_packages_shell() {
  log "Installing shell packages..."
  install_package_list "${PACKAGES_SHELL[@]}"

  # fzf: ensure version >= FZF_MIN_VERSION (apt version on Ubuntu is too old)
  install_fzf

  # Install starship
  install_starship

  # Install gum (go install works on all platforms, go is a runtime dependency)
  if ! command_exists gum; then
    log "Installing gum..."
    go install github.com/charmbracelet/gum@latest
  fi

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

  # Install fnm (replaces nvm)
  install_fnm

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

# Install fnm (Fast Node Manager — replaces nvm)
install_fnm() {
  if command_exists fnm; then
    log "fnm already installed: $(fnm --version)"
    return 0
  fi

  log "Installing fnm (Fast Node Manager)..."

  case "${OS_DISTRO}" in
    macos)  brew install fnm ;;
    arch)   maybe_sudo pacman -S --needed --noconfirm fnm ;;
    *)      curl -fsSL https://fnm.vercel.app/install | \
              bash --install-dir "${HOME}/.local/bin" --skip-shell ;;
  esac

  success "fnm installed"
}

# Clone a plugin repo if missing, pull to update if present.
_clone_or_update() {
  local dest="$1" url="$2" flags="${3:-}"
  if [[ ! -d "${dest}" ]]; then
    log "Cloning $(basename "${dest}")..."
    # shellcheck disable=SC2086
    git clone ${flags} "${url}" "${dest}"
  else
    log "Updating $(basename "${dest}")..."
    git -C "${dest}" pull --quiet
  fi
}

# Install zsh plugins to $XDG_DATA_HOME/zsh/plugins
install_zsh_plugins() {
  local plugin_dir="${XDG_DATA_HOME:-${HOME}/.local/share}/zsh/plugins"
  log "Installing zsh plugins to ${plugin_dir}..."
  mkdir -p "${plugin_dir}"

  # OMZ repo — shallow clone as plugin data source only (not sourced as framework)
  _clone_or_update "${plugin_dir}/ohmyzsh" \
    "https://github.com/ohmyzsh/ohmyzsh.git" "--depth 1"

  _clone_or_update "${plugin_dir}/zsh-autosuggestions" \
    "https://github.com/zsh-users/zsh-autosuggestions.git" "--depth 1"

  _clone_or_update "${plugin_dir}/zsh-completions" \
    "https://github.com/zsh-users/zsh-completions.git" "--depth 1"

  _clone_or_update "${plugin_dir}/evalcache" \
    "https://github.com/mroth/evalcache.git" "--depth 1"

  _clone_or_update "${plugin_dir}/fast-syntax-highlighting" \
    "https://github.com/zdharma-continuum/fast-syntax-highlighting.git" "--depth 1"

  # kubectl completion — generated, not cloned
  if command_exists kubectl; then
    log "Generating kubectl completion..."
    mkdir -p "${plugin_dir}/kubectl-autocomplete"
    kubectl completion zsh > "${plugin_dir}/kubectl-autocomplete/kubectl-autocomplete.plugin.zsh"
  fi

  success "zsh plugins installed to ${plugin_dir}"
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

# Install pi-coding-agent (pi.dev)
# Uses npm install -g; bootstraps fnm-managed node if npm is not yet in PATH
install_pi() {
  if command_exists pi; then
    log "pi-coding-agent is already installed"
    return 0
  fi

  log "Installing pi-coding-agent..."

  # Ensure npm is available; if fnm is installed, bootstrap a node version
  if ! command_exists npm; then
    local fnm_exec=""
    if command_exists fnm; then
      fnm_exec="fnm"
    elif [[ -x "${HOME}/.local/bin/fnm" ]]; then
      fnm_exec="${HOME}/.local/bin/fnm"
    fi

    if [[ -n "${fnm_exec}" ]]; then
      log "Bootstrapping Node.js via fnm..."
      "${fnm_exec}" install --lts 2>/dev/null || true
      eval "$("${fnm_exec}" env --shell bash 2>/dev/null)" || true
    fi
  fi

  if ! command_exists npm; then
    error "npm not found. Node.js is required to install pi-coding-agent."
    error "Install Node.js (e.g. fnm install --lts) and re-run."
    return 1
  fi

  npm install -g @mariozechner/pi-coding-agent

  if command_exists pi; then
    success "pi-coding-agent installed"
  else
    error "pi-coding-agent installation failed"
    return 1
  fi
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
export -f version_gte install_fzf
export -f install_starship install_fnm install_pyenv
export -f _clone_or_update install_zsh_plugins
export -f install_ohmyzsh install_pipx_packages
export -f install_docker install_pi
