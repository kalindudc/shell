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
