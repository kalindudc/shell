#!/usr/bin/env bash

# Setup script for shell dotfiles
# Installs oh-my-zsh plugins, generates configs, and runs stow

set -o errexit
set -o nounset
set -o pipefail

# Get script directory
SETUP_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_DIR="$(dirname "${SETUP_SCRIPT_DIR}")"

# Source library modules
# shellcheck source=src/lib/common.sh
source "${SETUP_SCRIPT_DIR}/lib/common.sh"
# shellcheck source=src/lib/state.sh
source "${SETUP_SCRIPT_DIR}/lib/state.sh"

# Configuration
export SHELL_DIR

# Display usage
usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Setup shell dotfiles and configurations.

OPTIONS:
  --help, -h       Show this help message
  --silent, -s     Run in silent mode (skip prompts)
  --stow           Run stow only

EOF
  exit 0
}

# Stow dotfiles
do_stow() {
  log "Stowing dotfiles to ${HOME}..."
  stow home -d "${SHELL_DIR}" -t "${HOME}" --adopt
  success "Dotfiles stowed successfully"
}

# Install oh-my-zsh plugins
install_ohmyzsh_plugins() {
  log "Installing oh-my-zsh plugins..."

  # Remove old installation and re-clone fresh
  rm -rf "${HOME}/.oh-my-zsh/"
  git clone https://github.com/ohmyzsh/ohmyzsh.git "${HOME}/.oh-my-zsh"

  # Clean up existing plugins
  local custom_dir="${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}"
  rm -rf "${custom_dir}/plugins/zsh-autosuggestions"
  rm -rf "${custom_dir}/plugins/zsh-syntax-highlighting"
  rm -rf "${custom_dir}/plugins/evalcache"
  rm -rf "${custom_dir}/plugins/enhancd"
  rm -rf "${custom_dir}/plugins/zsh-completions"

  # Clone plugins
  git clone https://github.com/zsh-users/zsh-autosuggestions \
    "${custom_dir}/plugins/zsh-autosuggestions"

  git clone https://github.com/zsh-users/zsh-syntax-highlighting.git \
    "${custom_dir}/plugins/zsh-syntax-highlighting"

  git clone https://github.com/mroth/evalcache \
    "${custom_dir}/plugins/evalcache"

  git clone https://github.com/b4b4r07/enhancd.git \
    "${custom_dir}/plugins/enhancd"

  git clone https://github.com/zsh-users/zsh-completions \
    "${custom_dir}/plugins/zsh-completions"

  # kubectl completion
  if command_exists kubectl; then
    mkdir -p "${custom_dir}/plugins/kubectl-autocomplete/"
    kubectl completion zsh > "${custom_dir}/plugins/kubectl-autocomplete/kubectl-autocomplete.plugin.zsh"
  fi

  success "oh-my-zsh plugins installed"
}

# Backup existing configs
backup_existing_configs() {
  log "Backing up existing configurations..."

  if [[ -f "${HOME}/.zshrc" ]]; then
    cp "${HOME}/.zshrc" "${HOME}/.zshrc.bak" 2>/dev/null || true
  fi
  if [[ -f "${HOME}/.p10k.zsh" ]]; then
    cp "${HOME}/.p10k.zsh" "${HOME}/.p10k.zsh.bak" 2>/dev/null || true
  fi
  if [[ -f "${HOME}/.config/direnv" ]]; then
    cp "${HOME}/.config/direnv" "${HOME}/.config/direnv.bak" 2>/dev/null || true
  fi
  if [[ -f "${HOME}/.vim" ]]; then
    cp "${HOME}/.vim" "${HOME}/.vim.bak" 2>/dev/null || true
  fi

  success "Existing configs backed up"
}

# Remove existing configs
remove_existing_configs() {
  log "Removing existing configurations..."

  rm -rf "${HOME}/.zshrc" 2>/dev/null || true
  rm -rf "${HOME}/.zcompdump" 2>/dev/null || true
  rm -rf "${HOME}/.p10k.zsh" 2>/dev/null || true
  rm -rf "${HOME}/.config/direnv" 2>/dev/null || true
  rm -rf "${HOME}/.vim" 2>/dev/null || true

  success "Existing configs removed"
}

# Install vim-plug
install_vim_plug() {
  log "Installing vim-plug..."

  curl -fLo "${HOME}/.vim/autoload/plug.vim" --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim >/dev/null 2>&1

  sh -c 'curl -fLo "${XDG_DATA_HOME:-${HOME}/.local/share}"/nvim/site/autoload/plug.vim --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim' >/dev/null 2>&1

  success "vim-plug installed"
}

# Generate .zshrc
generate_zshrc() {
  log "Generating ${HOME}/.zshrc..."

  "${SHELL_DIR}/src/generate_zshrc.rb"

  success ".zshrc generated"
}

# Prompt for git configuration
prompt_git_config() {
  local silent_mode="$1"

  # Load existing git config
  export GIT_EMAIL="${GIT_EMAIL:-$(git config --global user.email 2>/dev/null || echo "")}"
  export GIT_NAME="${GIT_NAME:-$(git config --global user.name 2>/dev/null || echo "")}"
  export GIT_SIGNING_KEY="${GIT_SIGNING_KEY:-$(git config --global user.signingkey 2>/dev/null || echo "")}"

  # Prompt for email if not set
  if [[ -z "${GIT_EMAIL}" ]] && [[ "${silent_mode}" == "false" ]]; then
    echo ""
    GIT_EMAIL="$(prompt_for_input "Please enter your email address:" "")"
    export GIT_EMAIL
  fi

  # Prompt for name if not set
  if [[ -z "${GIT_NAME}" ]] && [[ "${silent_mode}" == "false" ]]; then
    echo ""
    GIT_NAME="$(prompt_for_input "Please enter your full name:" "")"
    export GIT_NAME
  fi

  # Prompt for signing key if not set
  if [[ -z "${GIT_SIGNING_KEY}" ]] && [[ "${silent_mode}" == "false" ]]; then
    if prompt_for_yn "GIT signing key does not exist, do you want to generate a new signing key? (y/N)" "N"; then
      warn "Generating GPG key..."
      gpg --full-generate-key

      log "Listing GPG keys..."
      gpg --list-secret-keys --keyid-format LONG

      GIT_SIGNING_KEY="$(prompt_for_input "Please enter the GPG key ID from the above list:" "")"

      echo ""
      warn "Do not forget to add your key to GitHub: https://docs.github.com/en/authentication/managing-commit-signature-verification/generating-a-new-gpg-key"
    else
      echo ""
      log "Listing GPG keys..."
      gpg --list-secret-keys --keyid-format LONG
      GIT_SIGNING_KEY="$(prompt_for_input "Please enter your GPG key ID:" "")"
    fi

    export GIT_SIGNING_KEY
    echo ""
  fi

  # Save to state
  save_state_var "GIT_EMAIL" "${GIT_EMAIL}"
  save_state_var "GIT_NAME" "${GIT_NAME}"
  save_state_var "GIT_SIGNING_KEY" "${GIT_SIGNING_KEY}"

  # Save to local .env file in shell repo for portability
  local env_file="${SHELL_DIR}/.env"
  log "Saving git configuration to ${env_file}"

  cat > "${env_file}" <<EOF
# Git configuration
# This file is auto-generated by setup.sh
GIT_EMAIL=${GIT_EMAIL}
GIT_NAME=${GIT_NAME}
GIT_SIGNING_KEY=${GIT_SIGNING_KEY}
EOF

  chmod 600 "${env_file}"
  success "Git configuration saved to ${env_file}"
}

# Generate .gitconfig
generate_gitconfig() {
  log "Generating ${HOME}/.gitconfig..."

  "${SHELL_DIR}/src/generate_tempate.rb" \
    -i "${SHELL_DIR}/src/templates/.gitconfig.erb" \
    -o "${SHELL_DIR}/home/.gitconfig"

  success ".gitconfig generated"
}

# Setup GitHub CLI
setup_gh_auth() {
  local silent_mode="$1"

  if [[ "${silent_mode}" == "false" ]]; then
    if command_exists gh; then
      log "Setting up GitHub CLI authentication..."
      gh auth login
      gh auth setup-git
      success "GitHub CLI authenticated"
    fi
  else
    warn "Do not forget to run 'gh auth login && gh auth setup-git' to authenticate with GitHub"
  fi
}

# Main setup function
main() {
  local silent_mode=false

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --silent|-s)
        silent_mode=true
        export NONINTERACTIVE=1
        ;;
      --help|-h)
        usage
        ;;
      --stow)
        do_stow
        exit 0
        ;;
      *)
        error "Unknown option: $1"
        usage
        ;;
    esac
    shift
  done

  log "Shell Dotfiles Setup"
  echo ""

  # Initialize state management
  init_or_load_state

  # Step 1: Install oh-my-zsh plugins
  run_step "INSTALL_OHMYZSH_PLUGINS" \
    "Installing oh-my-zsh plugins" \
    install_ohmyzsh_plugins

  # Step 2: Backup existing configs
  run_step "BACKUP_CONFIGS" \
    "Backing up existing configurations" \
    backup_existing_configs

  # Step 3: Remove existing configs
  run_step "REMOVE_CONFIGS" \
    "Removing existing configurations" \
    remove_existing_configs

  # Step 4: Install vim-plug
  run_step "INSTALL_VIM_PLUG" \
    "Installing vim-plug" \
    install_vim_plug

  # Step 5: Generate .zshrc
  run_step "GENERATE_ZSHRC" \
    "Generating .zshrc" \
    generate_zshrc

  # Step 6: Prompt for git config (not wrapped in run_step as it's interactive)
  if ! is_step_complete "PROMPT_GIT_CONFIG"; then
    prompt_git_config "${silent_mode}"
    mark_step_complete "PROMPT_GIT_CONFIG"
  fi

  # Step 7: Generate .gitconfig
  run_step "GENERATE_GITCONFIG" \
    "Generating .gitconfig" \
    generate_gitconfig

  # Step 8: Stow dotfiles
  run_step "STOW_DOTFILES" \
    "Stowing dotfiles" \
    do_stow

  # Step 9: Setup GitHub CLI (not wrapped as it's interactive)
  if ! is_step_complete "SETUP_GH_AUTH"; then
    setup_gh_auth "${silent_mode}"
    mark_step_complete "SETUP_GH_AUTH"
  fi

  # Mark completion
  if command -v gdate &>/dev/null; then
    gdate > "${HOME}/.shell_setup_complete"
  else
    date > "${HOME}/.shell_setup_complete"
  fi

  echo ""
  success "Setup complete!"
  echo ""
  echo "Restart your shell to apply changes."
  echo ""
}

# Run main
main "$@"
