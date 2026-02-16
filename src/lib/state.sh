#!/usr/bin/env bash

# State management library
# Tracks installation state and preserves context variables for resume capability

set -o errexit
set -o nounset
set -o pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=src/lib/common.sh
source "${SCRIPT_DIR}/common.sh"

# State file paths (allow override for testing)
if [[ -z "${STATE_FILE:-}" ]]; then
  readonly STATE_FILE="${HOME}/.shell_install_state"
fi
if [[ -z "${LOCK_FILE:-}" ]]; then
  # Use project tmp directory if available, otherwise fall back to system tmp
  if [[ -n "${INSTALL_SCRIPT_DIR:-}" ]]; then
    mkdir -p "${INSTALL_SCRIPT_DIR}/tmp"
    readonly LOCK_FILE="${INSTALL_SCRIPT_DIR}/tmp/shell_install.lock"
  else
    # Fallback for when sourced outside install.sh
    readonly LOCK_FILE="${HOME}/.shell_install.lock"
  fi
fi
if [[ -z "${LOCK_TIMEOUT:-}" ]]; then
  readonly LOCK_TIMEOUT=300  # 5 minutes
fi

# Variables to preserve in state file (context variables)
readonly STATE_VARS=(
  "OS_TYPE"
  "OS_DISTRO"
  "OS_ARCH"
  "PACKAGE_MANAGER"
  "SHELL_DIR"
  "GIT_EMAIL"
  "GIT_NAME"
  "GIT_SIGNING_KEY"
  "HOMEBREW_PREFIX"
)

# Installation step variables (in execution order)
# These are set to "done" when each step completes
readonly STEP_VARS=(
  "OS_DETECT"
  "INSTALL_PACKAGE_MANAGER"
  "INSTALL_PACKAGES_CORE"
  "INSTALL_PACKAGES_SHELL"
  "INSTALL_PACKAGES_DEV"
  "INSTALL_PACKAGES_RUNTIMES"
  "INSTALL_PACKAGES_DEVOPS"
  "INSTALL_PACKAGES_FONTS"
  "INSTALL_PACKAGES_OPTIONAL"
  "INSTALL_PIPX_PACKAGES"
  "CLONE_SHELL_REPO"
  "RUN_SETUP"
  "SET_DEFAULT_SHELL"
)

# Create a new empty state file
create_state_file() {
  log "Initializing new installation state"
  touch "${STATE_FILE}"
  chmod 600 "${STATE_FILE}"
}

# Load all state variables from state file into environment
# This should be called ONCE at startup to hydrate all state into variables
load_state_from_file() {
  if [[ ! -f "${STATE_FILE}" ]]; then
    return 0
  fi

  log "Loading state from ${STATE_FILE}"

  # Source the state file to restore variables
  # shellcheck disable=SC1090
  set -o allexport
  source "${STATE_FILE}"
  set +o allexport
}

# Initialize state: create file if needed, then load state
# This is the standard entry point for state management
init_or_load_state() {
  if [[ -f "${STATE_FILE}" ]]; then
    load_state_from_file
  else
    create_state_file
  fi
}

# Save a state variable to the state file
# Usage: save_state_var "VAR_NAME" "value"
save_state_var() {
  local var_name="$1"
  local var_value="${2:-}"

  # Remove existing line for this variable (idempotent)
  if [[ -f "${STATE_FILE}" ]]; then
    sed -i.bak "/^${var_name}=/d" "${STATE_FILE}"
    rm -f "${STATE_FILE}.bak"
  fi

  # Append new value (quote value to handle spaces)
  printf '%s=%q\n' "${var_name}" "${var_value}" >> "${STATE_FILE}"
}



# Check if a step is complete
# Usage: is_step_complete "STEP_NAME"
# Returns: 0 if complete, 1 if not
is_step_complete() {
  local step_name="$1"

  # Use nameref to check the exported variable directly
  # This avoids reading the state file on every check
  local -n step_var="${step_name}" 2>/dev/null || return 1

  [[ "${step_var:-}" == "done" ]]
}

# Mark a step as complete
# Usage: mark_step_complete "STEP_NAME"
mark_step_complete() {
  local step_name="$1"

  # Save to file AND export to environment
  save_state_var "${step_name}" "done"
  export "${step_name}=done"
  success "Completed: ${step_name}"
}

# Run a step with state tracking
# Usage: run_step "STEP_NAME" "Description" command args...
run_step() {
  local step_name="$1"
  local description="$2"
  shift 2

  if is_step_complete "${step_name}"; then
    log "Skipping ${description} (already completed)"
    return 0
  fi

  log "${description}..."

  # execute the step command and check result
  if "$@"; then
    mark_step_complete "${step_name}"
    return 0
  else
    error "Failed: ${description}"
    return 1
  fi
}

# Acquire installation lock
acquire_lock() {
  local max_wait="${LOCK_TIMEOUT}"
  local waited=0

  # Check for existing lock
  while [[ -f "${LOCK_FILE}" ]]; do
    local lock_pid
    lock_pid="$(cat "${LOCK_FILE}" 2>/dev/null || echo "")"

    # Check if process is still running
    if [[ -n "${lock_pid}" ]] && kill -0 "${lock_pid}" 2>/dev/null; then
      if [[ ${waited} -ge ${max_wait} ]]; then
        abort "Another installation is running (PID: ${lock_pid}). Timeout after ${max_wait}s."
      fi

      warn "Another installation is running (PID: ${lock_pid}). Waiting..."
      sleep 5
      waited=$((waited + 5))
    else
      # Stale lock file
      warn "Removing stale lock file (PID: ${lock_pid})"
      rm -f "${LOCK_FILE}"
      break
    fi
  done

  # Create lock file with current PID
  echo "$$" > "${LOCK_FILE}"
  log "Acquired installation lock"
}

# Release installation lock
release_lock() {
  if [[ -f "${LOCK_FILE}" ]]; then
    local lock_pid
    lock_pid="$(cat "${LOCK_FILE}" 2>/dev/null || echo "")"

    # Only remove if it's our lock
    if [[ "${lock_pid}" == "$$" ]]; then
      rm -f "${LOCK_FILE}"
      log "Released installation lock"
    fi
  fi
}

# Clean up state and lock files
cleanup() {
  release_lock
}

# Reset installation state
reset_state() {
  if [[ -f "${STATE_FILE}" ]]; then
    log "Resetting installation state"
    rm -f "${STATE_FILE}"
    success "State reset complete"
  else
    warn "No state file found to reset"
  fi
}

# Display current state from environment variables
show_state() {
  log "Current installation state:"
  echo ""

  # Show variables
  echo "Variables:"
  for var in "${STATE_VARS[@]}"; do
    local value="${!var:-(not set)}"
    echo "  ${var}: ${value}"
  done

  echo ""
  echo "Completed steps:"
  local found_any=false
  for step in "${STEP_VARS[@]}"; do
    if [[ "${!step:-}" == "done" ]]; then
      echo "  - ${step}"
      found_any=true
    fi
  done

  if [[ "${found_any}" == "false" ]]; then
    echo "  (none)"
  fi
}

# Get state variable value from environment
# Usage: get_state_var "VAR_NAME"
get_state_var() {
  local var_name="$1"

  # Use indirect expansion to get variable value
  echo "${!var_name:-}"
}

# Save all current state variables
save_all_state_vars() {
  for var in "${STATE_VARS[@]}"; do
    # Get current value of variable
    local value="${!var:-}"
    if [[ -n "${value}" ]]; then
      save_state_var "${var}" "${value}"
    fi
  done
}

# Check if installation is resuming (has any completed steps)
# This checks if any step variable is set to "done"
is_resuming() {
  # Check if state file exists and has content
  if [[ ! -f "${STATE_FILE}" ]] || [[ ! -s "${STATE_FILE}" ]]; then
    return 1
  fi

  # Check if any step completion variable is set
  local step
  for step in "${STEP_VARS[@]}"; do
    if [[ "${!step:-}" == "done" ]]; then
      return 0
    fi
  done

  return 1
}

# Get list of completed steps from environment variables
get_completed_steps() {
  for step in "${STEP_VARS[@]}"; do
    if [[ "${!step:-}" == "done" ]]; then
      echo "${step}"
    fi
  done
}

# Get list of pending steps
get_pending_steps() {
  local all_steps=("$@")
  local completed_steps
  completed_steps="$(get_completed_steps)"

  for step in "${all_steps[@]}"; do
    if ! echo "${completed_steps}" | grep -q "^${step}$"; then
      echo "${step}"
    fi
  done
}

# Setup cleanup handlers
setup_cleanup_handlers() {
  trap cleanup EXIT
  trap cleanup SIGINT
  trap cleanup SIGTERM
}

# Export functions
export -f create_state_file save_state_var load_state_from_file init_or_load_state
export -f is_step_complete mark_step_complete run_step
export -f acquire_lock release_lock cleanup
export -f reset_state show_state get_state_var
export -f save_all_state_vars is_resuming
export -f get_completed_steps get_pending_steps
export -f setup_cleanup_handlers
