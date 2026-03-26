#!/usr/bin/env bats

# Unit tests for src/lib/packages.sh

setup() {
  # Source the libraries
  export NONINTERACTIVE=1
  source "${BATS_TEST_DIRNAME}/../../src/lib/common.sh"
  source "${BATS_TEST_DIRNAME}/../../src/lib/os_detect.sh"
  source "${BATS_TEST_DIRNAME}/../../src/lib/packages.sh"
  
  # Initialize OS detection
  detect_os
  detect_architecture
  detect_package_manager
}

@test "map_package_name maps fd correctly on Ubuntu" {
  override_os "ubuntu"
  
  mapped=$(map_package_name "fd")
  [ "$mapped" = "fd-find" ]
}

@test "map_package_name maps gpg correctly on all platforms" {
  override_os "ubuntu"
  mapped=$(map_package_name "gpg")
  [ "$mapped" = "gnupg" ]
  
  override_os "arch"
  mapped=$(map_package_name "gpg")
  [ "$mapped" = "gnupg" ]
  
  override_os "macos"
  mapped=$(map_package_name "gpg")
  [ "$mapped" = "gnupg" ]
}

@test "map_package_name returns empty for custom installs" {
  override_os "ubuntu"
  
  mapped=$(map_package_name "zoxide")
  [ -z "$mapped" ]
  
  mapped=$(map_package_name "git-delta")
  [ -z "$mapped" ]
}

@test "map_package_name handles AUR packages on Arch" {
  override_os "arch"
  
  # These should return empty (installed via AUR)
  mapped=$(map_package_name "go-task")
  [ -z "$mapped" ]
  
  mapped=$(map_package_name "git-delta")
  [ -z "$mapped" ]
}

@test "map_package_name maps gh correctly on Arch" {
  override_os "arch"
  
  mapped=$(map_package_name "gh")
  [ "$mapped" = "github-cli" ]
}

@test "map_package_name preserves regular package names" {
  override_os "ubuntu"
  
  mapped=$(map_package_name "git")
  [ "$mapped" = "git" ]
  
  mapped=$(map_package_name "curl")
  [ "$mapped" = "curl" ]
  
  mapped=$(map_package_name "stow")
  [ "$mapped" = "stow" ]
}

@test "is_package_installed checks for git" {
  # git should be installed if we got this far
  if command -v git >/dev/null 2>&1; then
    run is_package_installed "git"
    [ "$status" -eq 0 ]
  else
    skip "git not installed"
  fi
}

@test "PACKAGES_CORE contains required packages" {
  [[ " ${PACKAGES_CORE[@]} " =~ " git " ]]
  [[ " ${PACKAGES_CORE[@]} " =~ " curl " ]]
  [[ " ${PACKAGES_CORE[@]} " =~ " stow " ]]
  [[ " ${PACKAGES_CORE[@]} " =~ " ruby " ]]
}

@test "PACKAGES_SHELL contains shell tools" {
  [[ " ${PACKAGES_SHELL[@]} " =~ " zsh " ]]
  [[ " ${PACKAGES_SHELL[@]} " =~ " fzf " ]]
  [[ " ${PACKAGES_SHELL[@]} " =~ " ripgrep " ]]
}

@test "PACKAGES_DEV contains development tools" {
  [[ " ${PACKAGES_DEV[@]} " =~ " neovim " ]]
  [[ " ${PACKAGES_DEV[@]} " =~ " gh " ]]
  [[ " ${PACKAGES_DEV[@]} " =~ " gcc " ]]
}

# ── nvm removal ───────────────────────────────────────────────────────────────

@test "PACKAGES_CORE does not contain nvm" {
  # nvm is replaced by fnm; verify the intentional removal
  [[ ! " ${PACKAGES_CORE[*]} " =~ " nvm " ]]
}

@test "map_package_name has no entry for nvm" {
  override_os "ubuntu"
  mapped=$(map_package_name "nvm")
  [ "$mapped" = "nvm" ]  # falls through to default (returns unchanged name)
}

# ── _clone_or_update ──────────────────────────────────────────────────────────

setup_git_remote() {
  # Creates a minimal local git repo usable as a clone source. No network required.
  local remote="$1"
  git init -q "$remote"
  git -C "$remote" commit --allow-empty -q -m "init" \
    --author="Test <test@test>" 2>/dev/null || true
}

@test "_clone_or_update clones repo when destination is missing" {
  local remote="${BATS_TMPDIR}/remote-clone-$$"
  local dest="${BATS_TMPDIR}/dest-clone-$$"
  setup_git_remote "$remote"

  run _clone_or_update "$dest" "$remote"
  [ "$status" -eq 0 ]
  [ -d "$dest" ]
}

@test "_clone_or_update pulls when destination already exists" {
  local remote="${BATS_TMPDIR}/remote-pull-$$"
  local dest="${BATS_TMPDIR}/dest-pull-$$"
  setup_git_remote "$remote"
  git clone -q "$remote" "$dest"

  run _clone_or_update "$dest" "$remote"
  [ "$status" -eq 0 ]
  [ -d "$dest" ]
}

@test "_clone_or_update is idempotent" {
  local remote="${BATS_TMPDIR}/remote-idem-$$"
  local dest="${BATS_TMPDIR}/dest-idem-$$"
  setup_git_remote "$remote"

  _clone_or_update "$dest" "$remote"
  run _clone_or_update "$dest" "$remote"
  [ "$status" -eq 0 ]
}

# ── install_zsh_plugins ───────────────────────────────────────────────────────

@test "install_zsh_plugins creates plugin base directory" {
  export XDG_DATA_HOME="${BATS_TMPDIR}/xdg-base-$$"
  _clone_or_update() { mkdir -p "$1"; }
  kubectl() { return 1; }

  run install_zsh_plugins
  [ "$status" -eq 0 ]
  [ -d "${XDG_DATA_HOME}/zsh/plugins" ]
}

@test "install_zsh_plugins creates all expected plugin subdirectories" {
  export XDG_DATA_HOME="${BATS_TMPDIR}/xdg-dirs-$$"
  _clone_or_update() { mkdir -p "$1"; }
  # Exclude kubectl so command_exists returns false and we skip completion generation
  command_exists() { [[ "$1" != "kubectl" ]] && command -v "$1" &>/dev/null; }

  install_zsh_plugins

  local plugin_dir="${XDG_DATA_HOME}/zsh/plugins"
  [ -d "${plugin_dir}/ohmyzsh" ]
  [ -d "${plugin_dir}/zsh-autosuggestions" ]
  [ -d "${plugin_dir}/zsh-completions" ]
  [ -d "${plugin_dir}/evalcache" ]
  [ -d "${plugin_dir}/fast-syntax-highlighting" ]
}

@test "install_zsh_plugins generates kubectl completion when kubectl is available" {
  export XDG_DATA_HOME="${BATS_TMPDIR}/xdg-kubectl-$$"
  _clone_or_update() { mkdir -p "$1"; }
  kubectl() {
    [[ "$1" == "completion" ]] && echo "# kubectl completion zsh" && return 0
    return 1
  }

  install_zsh_plugins

  local completion="${XDG_DATA_HOME}/zsh/plugins/kubectl-autocomplete/kubectl-autocomplete.plugin.zsh"
  [ -f "$completion" ]
  grep -q "kubectl completion zsh" "$completion"
}

@test "install_zsh_plugins skips kubectl completion when kubectl is absent" {
  export XDG_DATA_HOME="${BATS_TMPDIR}/xdg-nokubectl-$$"
  _clone_or_update() { mkdir -p "$1"; }
  command_exists() { [[ "$1" != "kubectl" ]] && command -v "$1" &>/dev/null; }

  run install_zsh_plugins
  [ "$status" -eq 0 ]
  [ ! -f "${XDG_DATA_HOME}/zsh/plugins/kubectl-autocomplete/kubectl-autocomplete.plugin.zsh" ]
}

# ── install_fnm ───────────────────────────────────────────────────────────────

@test "install_fnm function is defined and exported" {
  # Consistent with the pattern for install_pyenv, install_starship etc.
  # Verify the function exists and is callable; actual installation belongs
  # in integration tests (requires network + sudo).
  run declare -F install_fnm
  [ "$status" -eq 0 ]
}
