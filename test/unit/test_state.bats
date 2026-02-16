#!/usr/bin/env bats

# Unit tests for src/lib/state.sh

setup() {
  # Set state file paths BEFORE sourcing (they become readonly)
  export STATE_FILE="${BATS_TMPDIR}/test_state_$$"
  export LOCK_FILE="${BATS_TMPDIR}/test_lock_$$"
  export LOCK_TIMEOUT=10
  
  # Source the libraries
  export NONINTERACTIVE=1
  source "${BATS_TEST_DIRNAME}/../../src/lib/common.sh"
  source "${BATS_TEST_DIRNAME}/../../src/lib/state.sh"
  
  # Clean up any existing files
  rm -f "${STATE_FILE}" "${LOCK_FILE}"
}

teardown() {
  # Clean up test files
  rm -f "${STATE_FILE}" "${LOCK_FILE}"
  rm -f "${STATE_FILE}.bak"
}

@test "create_state_file creates state file" {
  run create_state_file
  [ "$status" -eq 0 ]
  [ -f "${STATE_FILE}" ]
}

@test "save_state_var saves variable to state file" {
  create_state_file
  
  run save_state_var "TEST_VAR" "test_value"
  [ "$status" -eq 0 ]
  
  grep -q "TEST_VAR=test_value" "${STATE_FILE}"
}

@test "save_state_var is idempotent" {
  create_state_file
  
  save_state_var "TEST_VAR" "value1"
  save_state_var "TEST_VAR" "value2"
  
  # Should only have one entry
  count=$(grep -c "TEST_VAR=" "${STATE_FILE}")
  [ "$count" -eq 1 ]
  
  # Should have the latest value
  grep -q "TEST_VAR=value2" "${STATE_FILE}"
}

@test "load_state_from_file loads variables from state file" {
  create_state_file
  echo "TEST_VAR=loaded_value" >> "${STATE_FILE}"
  
  unset TEST_VAR
  load_state_from_file
  
  [ "$TEST_VAR" = "loaded_value" ]
}

@test "is_step_complete detects completed steps" {
  create_state_file
  
  run is_step_complete "TEST_STEP"
  [ "$status" -eq 1 ]
  
  # Write to file and load state to export variable
  echo "TEST_STEP=done" >> "${STATE_FILE}"
  load_state_from_file
  
  run is_step_complete "TEST_STEP"
  [ "$status" -eq 0 ]
}

@test "mark_step_complete marks step as done" {
  create_state_file
  
  run mark_step_complete "TEST_STEP"
  [ "$status" -eq 0 ]
  
  grep -q "TEST_STEP=done" "${STATE_FILE}"
}

@test "get_state_var retrieves variable value" {
  create_state_file
  echo "TEST_VAR=test_value" >> "${STATE_FILE}"
  load_state_from_file  # Load variables into environment
  
  value=$(get_state_var "TEST_VAR")
  [ "$value" = "test_value" ]
}

@test "is_resuming detects existing installation" {
  run is_resuming
  [ "$status" -eq 1 ]
  
  create_state_file
  mark_step_complete "OS_DETECT"  # Use actual step name from is_resuming
  
  run is_resuming
  [ "$status" -eq 0 ]
}

@test "get_completed_steps lists completed steps" {
  create_state_file
  # Use actual step names that get_completed_steps checks
  mark_step_complete "OS_DETECT"
  mark_step_complete "INSTALL_PACKAGE_MANAGER"
  
  completed=$(get_completed_steps)
  [[ "$completed" =~ "OS_DETECT" ]]
  [[ "$completed" =~ "INSTALL_PACKAGE_MANAGER" ]]
}

@test "acquire_lock creates lock file" {
  run acquire_lock
  [ "$status" -eq 0 ]
  [ -f "${LOCK_FILE}" ]
  
  # Lock file should contain current PID
  lock_pid=$(cat "${LOCK_FILE}")
  [ "$lock_pid" = "$$" ]
}

@test "release_lock removes lock file" {
  acquire_lock
  
  run release_lock
  [ "$status" -eq 0 ]
  [ ! -f "${LOCK_FILE}" ]
}

@test "acquire_lock handles stale locks" {
  # Create a stale lock with non-existent PID
  echo "99999" > "${LOCK_FILE}"
  
  run acquire_lock
  [ "$status" -eq 0 ]
  
  # Should have our PID now
  lock_pid=$(cat "${LOCK_FILE}")
  [ "$lock_pid" = "$$" ]
}

@test "cleanup releases lock" {
  acquire_lock
  
  run cleanup
  [ "$status" -eq 0 ]
  [ ! -f "${LOCK_FILE}" ]
}

@test "reset_state removes state file" {
  create_state_file
  mark_step_complete "TEST_STEP"
  
  run reset_state
  [ "$status" -eq 0 ]
  [ ! -f "${STATE_FILE}" ]
}
