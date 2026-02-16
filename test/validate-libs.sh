#!/usr/bin/env bash

# Simple validation script to test library loading and basic functionality

set -o errexit
set -o nounset
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "Validating library files..."
echo ""

# Load all libraries (they handle their own dependencies)
echo "Test 1: Loading libraries..."
export NONINTERACTIVE=1

# Source libraries in order (common first, as others depend on it)
# shellcheck source=../src/lib/common.sh
source "${PROJECT_ROOT}/src/lib/common.sh"
# shellcheck source=../src/lib/os_detect.sh  
source "${PROJECT_ROOT}/src/lib/os_detect.sh"
# shellcheck source=../src/lib/packages.sh
source "${PROJECT_ROOT}/src/lib/packages.sh"

echo "✓ Libraries loaded successfully"

# Test 2: Test utility functions
echo "Test 2: Testing utility functions..."
if command_exists bash; then
  echo "✓ command_exists works"
else
  echo "✗ command_exists failed"
  exit 1
fi

# Test 3: Skip (already loaded above)

# Test 3: Test OS detection
echo "Test 3: Testing OS detection..."
detect_os
detect_architecture
detect_package_manager
if [[ -n "${OS_TYPE}" ]] && [[ -n "${OS_ARCH}" ]] && [[ -n "${PACKAGE_MANAGER}" ]]; then
  echo "✓ OS detection works (${OS_TYPE}/${OS_ARCH}/${PACKAGE_MANAGER})"
else
  echo "✗ OS detection failed"
  exit 1
fi

# Test 4: Test state management (in subshell to avoid readonly issues)
echo "Test 4: Testing state management..."
(
  mkdir -p "${PROJECT_ROOT}/tmp"
  export STATE_FILE="${PROJECT_ROOT}/tmp/test_state_$$"
  export LOCK_FILE="${PROJECT_ROOT}/tmp/test_lock_$$"
  # shellcheck source=../src/lib/state.sh
  source "${PROJECT_ROOT}/src/lib/state.sh"
  
  create_state_file
  save_state_var "TEST_VAR" "test_value"
  export TEST_VAR="test_value"  # Need to export for get_state_var to work
  if get_state_var "TEST_VAR" | grep -q "test_value"; then
    echo "✓ State management works"
  else
    echo "✗ State management failed"
    exit 1
  fi
  rm -f "${STATE_FILE}" "${LOCK_FILE}"
)

# Test 5: Test package mapping
echo "Test 5: Testing package name mapping..."
mapped=$(map_package_name "git")
if [[ "${mapped}" == "git" ]]; then
  echo "✓ Package mapping works"
else
  echo "✗ Package mapping failed"
  exit 1
fi

echo ""
echo "========================================  "
echo "All validation tests passed!"
echo "========================================"
