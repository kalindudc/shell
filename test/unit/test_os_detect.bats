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

# ── detect_linux_distro ───────────────────────────────────────────────────────
# detect_linux_distro accepts an optional os-release file path, allowing tests
# to pass a temp file instead of relying on /etc/os-release.

_make_os_release() {
  # Usage: _make_os_release <file> <ID> [ID_LIKE]
  local file="$1" id="$2" id_like="${3:-}"
  printf 'ID=%s\n' "$id" > "$file"
  if [[ -n "$id_like" ]]; then
    printf 'ID_LIKE=%s\n' "$id_like" >> "$file"
  fi
}

@test "detect_linux_distro identifies ubuntu directly" {
  local f="${BATS_TMPDIR}/os-release-ubuntu-$$"
  _make_os_release "$f" "ubuntu"
  detect_linux_distro "$f"
  [ "$OS_DISTRO" = "ubuntu" ]
}

@test "detect_linux_distro identifies debian directly" {
  local f="${BATS_TMPDIR}/os-release-debian-$$"
  _make_os_release "$f" "debian"
  detect_linux_distro "$f"
  [ "$OS_DISTRO" = "ubuntu" ]
}

@test "detect_linux_distro identifies arch directly" {
  local f="${BATS_TMPDIR}/os-release-arch-$$"
  _make_os_release "$f" "arch"
  detect_linux_distro "$f"
  [ "$OS_DISTRO" = "arch" ]
}

@test "detect_linux_distro identifies manjaro directly" {
  local f="${BATS_TMPDIR}/os-release-manjaro-$$"
  _make_os_release "$f" "manjaro"
  detect_linux_distro "$f"
  [ "$OS_DISTRO" = "arch" ]
}

@test "detect_linux_distro uses ID_LIKE for arch derivatives (CachyOS)" {
  local f="${BATS_TMPDIR}/os-release-cachyos-$$"
  _make_os_release "$f" "cachyos" "arch"
  detect_linux_distro "$f"
  [ "$OS_DISTRO" = "arch" ]
}

@test "detect_linux_distro uses ID_LIKE for other arch derivatives" {
  local f="${BATS_TMPDIR}/os-release-endeavour-$$"
  _make_os_release "$f" "endeavouros" "arch"
  detect_linux_distro "$f"
  [ "$OS_DISTRO" = "arch" ]
}

@test "detect_linux_distro uses ID_LIKE for debian derivatives" {
  local f="${BATS_TMPDIR}/os-release-mint-$$"
  _make_os_release "$f" "linuxmint" "ubuntu debian"
  detect_linux_distro "$f"
  [ "$OS_DISTRO" = "ubuntu" ]
}

@test "detect_linux_distro falls back to ubuntu for fully unknown distro" {
  local f="${BATS_TMPDIR}/os-release-unknown-$$"
  _make_os_release "$f" "unknowndistro"
  detect_linux_distro "$f"
  [ "$OS_DISTRO" = "ubuntu" ]
}
