#!/usr/bin/env bats

# Unit tests for home/bin/lib/cli_common.sh

setup() {
  # Source the library
  source "${BATS_TEST_DIRNAME}/../../lib/cli_common.sh"

  # Isolated temp directory for each test
  export TEST_TMPDIR="${BATS_TMPDIR}/cli_common_test_$$"
  mkdir -p "${TEST_TMPDIR}"
}

teardown() {
  rm -rf "${TEST_TMPDIR}"
}

# ── cli_conf_dir ────────────────────────────────────────────────────

@test "cli_conf_dir returns default path when no override" {
  unset TESTAPP_CONF_DIR 2>/dev/null || true
  run cli_conf_dir "testapp"
  [ "${status}" -eq 0 ]
  [ "${output}" = "${HOME}/conf/testapp" ]
}

@test "cli_conf_dir respects env var override" {
  export TESTAPP_CONF_DIR="/tmp/custom_path"
  run cli_conf_dir "testapp"
  [ "${status}" -eq 0 ]
  [ "${output}" = "/tmp/custom_path" ]
  unset TESTAPP_CONF_DIR
}

# ── cli_ensure_conf ─────────────────────────────────────────────────

@test "cli_ensure_conf creates directory and files" {
  export TESTAPP_CONF_DIR="${TEST_TMPDIR}/testapp"
  cli_ensure_conf "testapp" "data.json:[]" "config.json:{}"
  [ -d "${TEST_TMPDIR}/testapp" ]
  [ -f "${TEST_TMPDIR}/testapp/data.json" ]
  [ -f "${TEST_TMPDIR}/testapp/config.json" ]
  [ "$(cat "${TEST_TMPDIR}/testapp/data.json")" = "[]" ]
  [ "$(cat "${TEST_TMPDIR}/testapp/config.json")" = "{}" ]
  unset TESTAPP_CONF_DIR
}

@test "cli_ensure_conf does not overwrite existing files" {
  export TESTAPP_CONF_DIR="${TEST_TMPDIR}/testapp"
  mkdir -p "${TEST_TMPDIR}/testapp"
  printf '%s' '["existing"]' > "${TEST_TMPDIR}/testapp/data.json"
  cli_ensure_conf "testapp" "data.json:[]"
  [ "$(cat "${TEST_TMPDIR}/testapp/data.json")" = '["existing"]' ]
  unset TESTAPP_CONF_DIR
}

# ── cli_conf_exists ─────────────────────────────────────────────────

@test "cli_conf_exists returns 0 when exists" {
  export TESTAPP_CONF_DIR="${TEST_TMPDIR}/testapp"
  mkdir -p "${TEST_TMPDIR}/testapp"
  run cli_conf_exists "testapp"
  [ "${status}" -eq 0 ]
  unset TESTAPP_CONF_DIR
}

@test "cli_conf_exists returns 1 when missing" {
  export TESTAPP_CONF_DIR="${TEST_TMPDIR}/nonexistent"
  run cli_conf_exists "testapp"
  [ "${status}" -eq 1 ]
  unset TESTAPP_CONF_DIR
}

# ── cli_require_conf ────────────────────────────────────────────────

@test "cli_require_conf exits on missing config" {
  export TESTAPP_CONF_DIR="${TEST_TMPDIR}/nonexistent"
  run cli_require_conf "testapp"
  [ "${status}" -ne 0 ]
  [[ "${output}" =~ "init" ]]
  unset TESTAPP_CONF_DIR
}

# ── cli_print_help ──────────────────────────────────────────────────

@test "cli_print_help formats help output" {
  run cli_print_help "mytool" "A test tool" "cmd1|Do first thing" "cmd2|Do second thing"
  [ "${status}" -eq 0 ]
  [[ "${output}" =~ "mytool" ]]
  [[ "${output}" =~ "A test tool" ]]
  [[ "${output}" =~ "cmd1" ]]
  [[ "${output}" =~ "Do first thing" ]]
  [[ "${output}" =~ "cmd2" ]]
}

# ── cli_color ───────────────────────────────────────────────────────

@test "cli_color outputs ANSI codes" {
  unset NO_COLOR 2>/dev/null || true
  result="$(cli_color red "hello")"
  [[ "${result}" =~ $'\033' ]]
  [[ "${result}" =~ "hello" ]]
}

@test "cli_color suppresses codes when NO_COLOR is set" {
  export NO_COLOR=1
  result="$(cli_color red "hello")"
  [ "${result}" = "hello" ]
  unset NO_COLOR
}

@test "cli_color passes through unknown color" {
  unset NO_COLOR 2>/dev/null || true
  result="$(cli_color unknown "text")"
  [ "${result}" = "text" ]
}

# ── cli_date_today ──────────────────────────────────────────────────

@test "cli_date_today returns YYYY-MM-DD format" {
  run cli_date_today
  [ "${status}" -eq 0 ]
  [[ "${output}" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]
}
