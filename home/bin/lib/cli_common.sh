#!/usr/bin/env bash
# Shared CLI library for home/bin/ tools
# Source this file -- do not execute directly.
#
# shellcheck disable=SC2059

set -euo pipefail

# ── Colors ──────────────────────────────────────────────────────────

cli_color() {
  local color="$1"
  shift
  local text="$*"

  # Respect NO_COLOR (https://no-color.org/)
  if [[ -n "${NO_COLOR:-}" ]]; then
    printf '%s' "${text}"
    return
  fi

  local code=""
  case "${color}" in
    red)     code='\033[0;31m' ;;
    green)   code='\033[0;32m' ;;
    yellow)  code='\033[1;33m' ;;
    blue)    code='\033[0;34m' ;;
    cyan)    code='\033[0;36m' ;;
    magenta) code='\033[0;35m' ;;
    bold)    code='\033[1m'    ;;
    dim)     code='\033[2m'    ;;
    *)
      printf '%s' "${text}"
      return
      ;;
  esac

  printf "${code}%s\033[0m" "${text}"
}

# ── Configuration directory ─────────────────────────────────────────

cli_conf_dir() {
  local tool_name="$1"
  local override_var="${tool_name^^}_CONF_DIR"
  echo "${!override_var:-${HOME}/conf/${tool_name}}"
}

cli_ensure_conf() {
  local tool_name="$1"
  shift

  local conf_dir
  conf_dir="$(cli_conf_dir "${tool_name}")"
  mkdir -p "${conf_dir}"

  local entry file default_content
  for entry in "$@"; do
    file="${entry%%:*}"
    default_content="${entry#*:}"
    if [[ ! -f "${conf_dir}/${file}" ]]; then
      printf '%s' "${default_content}" > "${conf_dir}/${file}"
    fi
  done
}

cli_conf_exists() {
  local tool_name="$1"
  local conf_dir
  conf_dir="$(cli_conf_dir "${tool_name}")"

  if [[ -d "${conf_dir}" ]]; then
    return 0
  fi

  printf "Configuration directory not found: %s\n" "${conf_dir}" >&2
  return 1
}

cli_require_conf() {
  local tool_name="$1"
  if ! cli_conf_exists "${tool_name}"; then
    printf "configuration not found, run '%s init'\n" "${tool_name}" >&2
    exit 1
  fi
}

# ── Help formatting ─────────────────────────────────────────────────

cli_print_help() {
  local tool_name="$1"
  local description="$2"
  shift 2

  printf '%s - %s\n\n' "$(cli_color bold "${tool_name}")" "${description}"
  printf 'usage: %s <command> [options]\n\n' "${tool_name}"
  printf 'Available commands:\n'

  local entry cmd desc
  for entry in "$@"; do
    cmd="${entry%%|*}"
    desc="${entry#*|}"
    printf '  %-30s %s\n' "${cmd}" "${desc}"
  done
  printf '\n'
}

# ── Subcommand help ──────────────────────────────────────────────────

cli_print_subcmd_help() {
  local tool_name="$1"
  local subcmd="$2"
  local usage="$3"
  local description="$4"
  shift 4

  printf '%s %s - %s\n\n' "$(cli_color bold "${tool_name}")" "${subcmd}" "${description}"
  printf 'usage: %s\n\n' "${usage}"

  if [[ $# -gt 0 ]]; then
    printf 'Options:\n'
    local entry flag fdesc
    for entry in "$@"; do
      flag="${entry%%|*}"
      fdesc="${entry#*|}"
      printf '  %-28s %s\n' "${flag}" "${fdesc}"
    done
    printf '\n'
  fi
}

# ── Date helper ─────────────────────────────────────────────────────

cli_date_today() {
  date +%Y-%m-%d
}
