#!/usr/bin/env bash

# Common utility functions for shell installation scripts
# Following best practices from https://sharats.me/posts/shell-script-best-practices/

set -o errexit
set -o nounset
set -o pipefail

# Enable debug mode if TRACE is set
if [[ "${TRACE-0}" == "1" ]]; then
  set -o xtrace
fi

# Color codes (only define if not already set)
if [[ -z "${RED:-}" ]]; then
  readonly RED='\033[0;31m'
  readonly GREEN='\033[0;32m'
  readonly YELLOW='\033[1;33m'
  readonly BLUE='\033[0;34m'
  readonly BOLD='\033[1m'
  readonly NC='\033[0m' # No Color

  # Terminal control codes
  readonly TTYDEV="/dev/tty"
  readonly TTY_RESET=$'\033[0m'
  readonly TTY_BOLD=$'\033[1m'
  readonly TTY_UNDERLINE=$'\033[4m'
fi

# Pretty print functions
log() {
  echo -e "${BLUE}==>${BOLD} $*${NC}" >&2
}

warn() {
  echo -e "${YELLOW}Warning:${NC} $*" >&2
}

error() {
  echo -e "${RED}Error:${NC} $*" >&2
}

abort() {
  error "$@"
  exit 1
}

success() {
  echo -e "${GREEN}✓${NC} $*" >&2
}

# Prompt for yes/no with default
# Usage: prompt_for_yn "Do you want to continue?" "Y"
# Returns: 0 for yes, 1 for no
prompt_for_yn() {
  local prompt="$1"
  local default="${2:-N}"
  local answer

  # In non-interactive mode, use default
  if [[ "${NONINTERACTIVE-0}" == "1" ]]; then
    echo "${default}"
    return 0
  fi

  while true; do
    if [[ -t 0 ]]; then
      read -r -p "${prompt} " answer <"${TTYDEV}"
    else
      read -r -p "${prompt} " answer
    fi

    answer="${answer:-${default}}"

    case "${answer}" in
      [Yy]* ) return 0;;
      [Nn]* ) return 1;;
      * ) echo "Please answer y or n.";;
    esac
  done
}

# Prompt for input with default
# Usage: prompt_for_input "Enter your name:" "default"
# Prints: the user input or default
prompt_for_input() {
  local prompt="$1"
  local default="${2:-}"
  local value

  # In non-interactive mode, use default
  if [[ "${NONINTERACTIVE-0}" == "1" ]]; then
    echo "${default}"
    return 0
  fi

  if [[ -t 0 ]]; then
    read -r -p "${prompt} " value <"${TTYDEV}"
  else
    read -r -p "${prompt} " value
  fi

  echo "${value:-${default}}"
}

# Join array elements with a delimiter
# Usage: shell_join "," "${array[@]}"
shell_join() {
  local separator="$1"
  shift
  local first="$1"
  shift
  printf "%s" "${first}" "${@/#/${separator}}"
}

# Remove trailing newline
chomp() {
  printf "%s" "${1%$'\n'}"
}

# Execute a command and display it
execute() {
  log "$@"
  if ! "$@"; then
    abort "Failed to execute: $*"
  fi
}

# Execute a command quietly
execute_quiet() {
  if ! "$@" >/dev/null 2>&1; then
    abort "Failed to execute: $*"
  fi
}

# Retry a command with exponential backoff
# Usage: retry 3 5 command arg1 arg2
# Args: max_attempts, delay, command...
retry() {
  local max_attempts="$1"
  local delay="$2"
  shift 2
  local attempt=1
  local exit_code=0

  while [[ ${attempt} -le ${max_attempts} ]]; do
    if "$@"; then
      return 0
    else
      exit_code=$?
      if [[ ${attempt} -lt ${max_attempts} ]]; then
        warn "Command failed (attempt ${attempt}/${max_attempts}). Retrying in ${delay}s..."
        sleep "${delay}"
        delay=$((delay * 2))
      fi
      attempt=$((attempt + 1))
    fi
  done

  error "Command failed after ${max_attempts} attempts: $*"
  return ${exit_code}
}

# Ring the terminal bell
ring_bell() {
  if [[ -t 1 ]]; then
    printf "\a"
  fi
}

# Wait for user to press enter
wait_for_user() {
  local message="${1:-Press RETURN to continue or any other key to abort...}"

  if [[ "${NONINTERACTIVE-0}" == "1" ]]; then
    return 0
  fi

  if [[ -t 0 ]]; then
    read -r -p "${message}" <"${TTYDEV}"
  else
    read -r -p "${message}"
  fi
}

# Version comparison functions
# Returns: 0 if comparison is true, 1 otherwise

version_gt() {
  [[ "${1%.*}" -gt "${2%.*}" ]] || [[ "${1%.*}" -eq "${2%.*}" && "${1#*.}" -gt "${2#*.}" ]]
}

version_ge() {
  [[ "${1%.*}" -gt "${2%.*}" ]] || [[ "${1%.*}" -eq "${2%.*}" && "${1#*.}" -ge "${2#*.}" ]]
}

version_lt() {
  [[ "${1%.*}" -lt "${2%.*}" ]] || [[ "${1%.*}" -eq "${2%.*}" && "${1#*.}" -lt "${2#*.}" ]]
}

version_le() {
  [[ "${1%.*}" -lt "${2%.*}" ]] || [[ "${1%.*}" -eq "${2%.*}" && "${1#*.}" -le "${2#*.}" ]]
}

version_eq() {
  [[ "${1}" == "${2}" ]]
}

# Check if command exists
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Check if running as root
is_root() {
  [[ "${EUID}" -eq 0 ]]
}

# Get script directory
get_script_dir() {
  local source="${BASH_SOURCE[0]}"
  while [[ -L "${source}" ]]; do
    local dir
    dir="$(cd -P "$(dirname "${source}")" && pwd)"
    source="$(readlink "${source}")"
    [[ ${source} != /* ]] && source="${dir}/${source}"
  done
  cd -P "$(dirname "${source}")" && pwd
}

# Ensure running on supported architecture
check_architecture() {
  local arch
  arch="$(uname -m)"

  case "${arch}" in
    x86_64|amd64|arm64|aarch64)
      return 0
      ;;
    *)
      abort "Unsupported architecture: ${arch}. Supported: x86_64, arm64"
      ;;
  esac
}

# Check if running in CI environment
is_ci() {
  [[ -n "${CI-}" ]] || [[ -n "${GITHUB_ACTIONS-}" ]] || [[ -n "${GITLAB_CI-}" ]]
}

# Get number of CPU cores
get_cpu_cores() {
  if command_exists nproc; then
    nproc
  elif command_exists sysctl; then
    sysctl -n hw.ncpu
  else
    echo "1"
  fi
}

# Create a temporary directory
make_temp_dir() {
  mktemp -d -t shell-install-XXXXXX
}

# Safe directory navigation
safe_cd() {
  local dir="$1"
  if [[ ! -d "${dir}" ]]; then
    abort "Directory does not exist: ${dir}"
  fi
  cd "${dir}" || abort "Failed to change to directory: ${dir}"
}

# Set zsh as the default shell
set_default_shell() {
  local zsh_path
  local current_shell

  # Get current shell
  current_shell="${SHELL:-}"

  # Find zsh path - try multiple methods
  if command -v zsh >/dev/null 2>&1; then
    zsh_path="$(command -v zsh)"
  elif [[ -x /usr/bin/zsh ]]; then
    zsh_path="/usr/bin/zsh"
  elif [[ -x /bin/zsh ]]; then
    zsh_path="/bin/zsh"
  elif [[ -x /usr/local/bin/zsh ]]; then
    zsh_path="/usr/local/bin/zsh"
  else
    error "zsh is not installed or not found in common paths"
    warn "Tried: command -v zsh, /usr/bin/zsh, /bin/zsh, /usr/local/bin/zsh"
    return 1
  fi

  log "Found zsh at: ${zsh_path}"

  # Check if already using zsh
  if [[ "${current_shell}" == "${zsh_path}" ]]; then
    log "zsh is already the default shell"
    return 0
  fi

  # Ensure zsh is in /etc/shells
  if ! grep -q "^${zsh_path}$" /etc/shells 2>/dev/null; then
    log "Adding zsh to /etc/shells..."
    if is_root; then
      echo "${zsh_path}" >> /etc/shells
    else
      echo "${zsh_path}" | sudo tee -a /etc/shells >/dev/null
    fi
  fi

  # Change default shell
  log "Setting zsh as default shell..."
  if [[ "${NONINTERACTIVE:-0}" == "1" ]]; then
    # Non-interactive mode: just log what would happen
    log "Non-interactive mode: would run 'chsh -s ${zsh_path}'"
    log "Manual action required: Run 'chsh -s ${zsh_path}' to set zsh as default"
    return 0
  else
    # Interactive mode: actually change the shell
    if chsh -s "${zsh_path}"; then
      success "Default shell changed to zsh"
      warn "You must log out and log back in (or reboot) for the change to take effect"
      return 0
    else
      error "Failed to change default shell"
      warn "You can manually set it later with: chsh -s ${zsh_path}"
      return 1
    fi
  fi
}

# Export functions for use in subshells
export -f log warn error abort success
export -f prompt_for_yn prompt_for_input
export -f shell_join chomp
export -f execute execute_quiet retry
export -f ring_bell wait_for_user
export -f version_gt version_ge version_lt version_le version_eq
export -f command_exists is_root is_ci
export -f get_script_dir get_cpu_cores
export -f check_architecture
export -f make_temp_dir safe_cd set_default_shell
