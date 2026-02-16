#!/usr/bin/env bash

# Unified installation script for shell dotfiles
# Supports macOS (Homebrew), Ubuntu/Debian (apt), and Arch Linux (pacman/yay)

set -o errexit
set -o nounset
set -o pipefail

# Enable debug mode if TRACE is set
if [[ "${TRACE-0}" == "1" ]]; then
  set -o xtrace
fi

# Bootstrap: If running via curl (no source file), clone repo and re-execute
# This block runs ONLY when the script is piped from curl
# After exec, this process is replaced and won't continue
if [[ "${BASH_SOURCE[0]:-}" == "" ]] || [[ "${BASH_SOURCE[0]}" == "bash" ]]; then
  echo "===> Detected execution via curl, bootstrapping..."
  
  # Determine installation directory (allow override via env var)
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
    # Install git if not present
    if ! command -v git >/dev/null 2>&1; then
      echo "===> Installing git..."
      if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq && apt-get install -y git >/dev/null 2>&1
      elif command -v pacman >/dev/null 2>&1; then
        pacman -Sy --noconfirm git >/dev/null 2>&1
      elif command -v brew >/dev/null 2>&1; then
        brew install git >/dev/null 2>&1
      else
        echo "Error: Unable to install git. Please install git manually."
        exit 1
      fi
    fi
    
    # Clone repo to permanent location
    echo "===> Cloning repository..."
    mkdir -p "${BOOTSTRAP_CLONE_DIR}"
    git clone --depth 1 https://github.com/kalindudc/shell.git "${BOOTSTRAP_SHELL_DIR}"
  fi
  
  echo "===> Re-executing from cloned repository..."
  cd "${BOOTSTRAP_SHELL_DIR}"
  exec bash "${BOOTSTRAP_SHELL_DIR}/install.sh" "$@"
  
  # If exec fails (should never reach here), exit explicitly
  echo "Error: Failed to execute cloned script"
  exit 1
fi

# Get script directory
INSTALL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source library modules
# shellcheck source=src/lib/common.sh
source "${INSTALL_SCRIPT_DIR}/src/lib/common.sh"
# shellcheck source=src/lib/os_detect.sh
source "${INSTALL_SCRIPT_DIR}/src/lib/os_detect.sh"
# shellcheck source=src/lib/state.sh
source "${INSTALL_SCRIPT_DIR}/src/lib/state.sh"
# shellcheck source=src/lib/packages.sh
source "${INSTALL_SCRIPT_DIR}/src/lib/packages.sh"

# Installation configuration
readonly GIT_CLONE_DIR="${HOME}/src/github.com/kalindudc"
readonly SHELL_REMOTE="https://github.com/kalindudc/shell.git"

# Installation flags
SKIP_CATEGORIES=()
RESET_STATE=false
CONTINUE_INSTALL=false
OS_OVERRIDE=""

# Display usage information
usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Unified installation script for shell dotfiles and development environment.

OPTIONS:
  --help, -h              Show this help message
  --skip-category=CAT     Skip installation category (core, shell, dev, runtimes, devops, fonts, optional)
  --reset-state           Reset installation state and start fresh
  --continue              Continue from last successful step
  --os=OS                 Override OS detection (macos, ubuntu, arch)
  --noninteractive        Run in non-interactive mode
  --trace                 Enable debug tracing
  --show-state            Show current installation state
  --stow                  Run stow only (skip installation)

EXAMPLES:
  ./install.sh                              # Auto-detect and install everything
  ./install.sh --skip-category=fonts        # Skip font installation
  ./install.sh --continue                   # Resume from last step
  ./install.sh --reset-state                # Start fresh
  NONINTERACTIVE=1 ./install.sh             # Non-interactive mode
  TRACE=1 ./install.sh                      # Debug mode

EOF
  exit 0
}

# Parse command line arguments
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h)
        usage
        ;;
      --skip-category=*)
        SKIP_CATEGORIES+=("${1#*=}")
        ;;
      --reset-state)
        RESET_STATE=true
        ;;
      --continue)
        CONTINUE_INSTALL=true
        ;;
      --os=*)
        OS_OVERRIDE="${1#*=}"
        ;;
      --noninteractive)
        export NONINTERACTIVE=1
        ;;
      --trace)
        export TRACE=1
        set -o xtrace
        ;;
      --show-state)
        init_or_load_state
        show_state
        exit 0
        ;;
      --stow)
        "${INSTALL_SCRIPT_DIR}/src/setup.sh" --stow
        exit 0
        ;;
      *)
        error "Unknown option: $1"
        usage
        ;;
    esac
    shift
  done
}

# Check if category should be skipped
should_skip_category() {
  local category="$1"

  for skip in "${SKIP_CATEGORIES[@]}"; do
    if [[ "${skip}" == "${category}" ]]; then
      return 0
    fi
  done

  return 1
}

# Clone or update shell repository
setup_shell_repo() {
  mkdir -p "${GIT_CLONE_DIR}"

  SHELL_DIR="${GIT_CLONE_DIR}/shell"
  export SHELL_DIR
  save_state_var "SHELL_DIR" "${SHELL_DIR}"

  if [[ -d "${SHELL_DIR}" ]]; then
    if prompt_for_yn "${SHELL_DIR} exists. Overwrite with upstream changes? (y/N)" "N"; then
      log "Updating ${SHELL_DIR}..."
      (
        cd "${SHELL_DIR}"
        git reset --hard
        git clean -fd
        git pull origin main
      )
      success "Repository updated"
    else
      log "Using existing ${SHELL_DIR}"
    fi
  else
    log "Cloning repository to ${SHELL_DIR}..."
    git clone "${SHELL_REMOTE}" "${SHELL_DIR}"
    success "Repository cloned"
  fi
}

# Main installation orchestration
main() {
  log "Shell Dotfiles Installation"
  echo ""

  # Parse arguments
  parse_args "$@"

  # Setup cleanup handlers
  setup_cleanup_handlers

  # Acquire installation lock
  acquire_lock

  # Handle state reset
  if [[ "${RESET_STATE}" == "true" ]]; then
    reset_state
  fi

  # Initialize state management: create file if needed, then load ALL state once
  # shellcheck disable=SC2154  # STATE_FILE is defined in state.sh
  if [[ -f "${STATE_FILE}" ]]; then
    log "Found existing installation state at ${STATE_FILE}"
    load_state_from_file  # Load ALL variables into environment ONCE
    
    # Check if resuming and prompt user
    if is_resuming && [[ "${CONTINUE_INSTALL}" == "false" ]]; then
      if prompt_for_yn "Previous installation found. Continue from last step? (Y/n)" "Y"; then
        CONTINUE_INSTALL=true
      else
        reset_state
        create_state_file
      fi
    fi
  else
    log "No existing state found, starting fresh installation"
    create_state_file
  fi

  # Step 1: OS Detection
  if ! is_step_complete "OS_DETECT"; then
    log "Detecting operating system..."

    if [[ -n "${OS_OVERRIDE}" ]]; then
      override_os "${OS_OVERRIDE}"
    else
      init_os_detection
    fi

    save_all_state_vars
    mark_step_complete "OS_DETECT"
  else
    log "Skipping OS detection (already completed)"
  fi

  # Step 2: Install Package Manager
  run_step "INSTALL_PACKAGE_MANAGER" \
    "Ensuring package manager is installed" \
    ensure_package_manager

  save_all_state_vars

  # Step 3: Install Core Packages
  if ! should_skip_category "core"; then
    run_step "INSTALL_PACKAGES_CORE" \
      "Installing core packages (git, curl, stow, ruby)" \
      install_packages_core
  fi

  # Step 4: Install Shell Packages
  if ! should_skip_category "shell"; then
    run_step "INSTALL_PACKAGES_SHELL" \
      "Installing shell packages (zsh, fzf, ripgrep, zoxide)" \
      install_packages_shell
  fi

  # Step 5: Install Development Packages
  if ! should_skip_category "dev"; then
    run_step "INSTALL_PACKAGES_DEV" \
      "Installing development packages (neovim, gh, gcc)" \
      install_packages_dev
  fi

  # Step 6: Install Runtime Packages
  if ! should_skip_category "runtimes"; then
    run_step "INSTALL_PACKAGES_RUNTIMES" \
      "Installing runtime packages (pyenv, nvm, go)" \
      install_packages_runtimes
  fi

  # Step 7: Install DevOps Packages
  if ! should_skip_category "devops"; then
    run_step "INSTALL_PACKAGES_DEVOPS" \
      "Installing DevOps packages (kubectl, helm)" \
      install_packages_devops
  fi

  # Step 8: Install Fonts
  if ! should_skip_category "fonts"; then
    run_step "INSTALL_PACKAGES_FONTS" \
      "Installing Nerd Fonts" \
      install_packages_fonts
  fi

  # Step 9: Install Optional Packages
  if ! should_skip_category "optional"; then
    run_step "INSTALL_PACKAGES_OPTIONAL" \
      "Installing optional packages (vscode, ghostty)" \
      install_packages_optional
  fi

  # Step 10: Install pipx packages
  run_step "INSTALL_PIPX_PACKAGES" \
    "Installing pipx packages" \
    install_pipx_packages

  # Step 11: Clone/Update Shell Repository
  run_step "CLONE_SHELL_REPO" \
    "Setting up shell repository" \
    setup_shell_repo

  # Step 12: Run setup script
  if ! is_step_complete "RUN_SETUP"; then
    log "Running setup script..."
    if [[ "${NONINTERACTIVE:-0}" == "1" ]]; then
      "${SHELL_DIR}/src/setup.sh" --silent
    else
      "${SHELL_DIR}/src/setup.sh"
    fi
    mark_step_complete "RUN_SETUP"
  fi

  # Step 13: Set zsh as default shell (FINAL STEP)
  if ! should_skip_category "shell"; then
    run_step "SET_DEFAULT_SHELL" \
      "Setting zsh as default shell" \
      set_default_shell
  fi

  # Installation complete
  echo ""
  success "Installation complete!"
  echo ""

  # Display next steps
  cat <<'EOF'

Next Steps:

1. Log out and log back in (or reboot) for shell changes to take effect
2. After re-login, your default shell will be zsh
3. If you skipped any steps, you can resume with: ./install.sh --continue
4. To reset and start fresh: ./install.sh --reset-state
5. To see installation state: ./install.sh --show-state

Additional Configuration:

- Configure starship: Edit ~/.config/starship.toml
- Install Node.js: nvm install node
- Install Python: pyenv install 3.11

Troubleshooting:

- Debug mode: TRACE=1 ./install.sh
- Skip category: ./install.sh --skip-category=fonts
- Manual stow: ./install.sh --stow
- Set shell manually: chsh -s $(which zsh)

EOF

  ring_bell
}

# Run main function
main "$@"
