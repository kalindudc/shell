#!/usr/bin/env bats

# Unit tests for src/lib/os_detect.sh

setup() {
  # Source the libraries
  export NONINTERACTIVE=1
  source "${BATS_TEST_DIRNAME}/../../src/lib/common.sh"
  source "${BATS_TEST_DIRNAME}/../../src/lib/os_detect.sh"
}

@test "detect_os identifies operating system" {
  detect_os
  [ -n "$OS_TYPE" ]
  [ -n "$OS_DISTRO" ]
}

@test "detect_architecture identifies architecture" {
  detect_architecture
  [ -n "$OS_ARCH" ]
  [[ "$OS_ARCH" =~ ^(x86_64|arm64)$ ]]
}

@test "detect_package_manager identifies package manager" {
  detect_os
  detect_architecture
  detect_package_manager
  [ -n "$PACKAGE_MANAGER" ]
}

@test "is_macos returns correct value" {
  detect_os
  
  if [[ "$(uname -s)" == "Darwin" ]]; then
    run is_macos
    [ "$status" -eq 0 ]
  else
    run is_macos
    [ "$status" -eq 1 ]
  fi
}

@test "is_linux returns correct value" {
  detect_os
  
  if [[ "$(uname -s)" == "Linux" ]]; then
    run is_linux
    [ "$status" -eq 0 ]
  else
    run is_linux
    [ "$status" -eq 1 ]
  fi
}

@test "override_os changes OS detection" {
  override_os "ubuntu"
  [ "$OS_TYPE" = "linux" ]
  [ "$OS_DISTRO" = "ubuntu" ]
  
  override_os "macos"
  [ "$OS_TYPE" = "macos" ]
  [ "$OS_DISTRO" = "macos" ]
}

@test "override_os rejects invalid OS" {
  run override_os "invalid_os"
  [ "$status" -eq 1 ]
}

@test "get_distro returns distribution name" {
  detect_os
  distro=$(get_distro)
  [ -n "$distro" ]
}

@test "get_architecture returns architecture" {
  detect_architecture
  arch=$(get_architecture)
  [ -n "$arch" ]
  [[ "$arch" =~ ^(x86_64|arm64)$ ]]
}

@test "get_os_type returns OS type" {
  detect_os
  os_type=$(get_os_type)
  [ -n "$os_type" ]
  [[ "$os_type" =~ ^(macos|linux)$ ]]
}
