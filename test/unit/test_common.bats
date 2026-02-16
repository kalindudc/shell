#!/usr/bin/env bats

# Unit tests for src/lib/common.sh

setup() {
  # Source the library
  export NONINTERACTIVE=1
  source "${BATS_TEST_DIRNAME}/../../src/lib/common.sh"
}

@test "log prints message to stderr" {
  run log "Test message"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Test message" ]]
}

@test "warn prints warning message" {
  run warn "Test warning"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Warning" ]]
  [[ "$output" =~ "Test warning" ]]
}

@test "error prints error message" {
  run error "Test error"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Error" ]]
  [[ "$output" =~ "Test error" ]]
}

@test "abort exits with error" {
  run abort "Fatal error"
  [ "$status" -eq 1 ]
  [[ "$output" =~ "Error" ]]
  [[ "$output" =~ "Fatal error" ]]
}

@test "success prints success message" {
  run success "Operation completed"
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Operation completed" ]]
}

@test "version_gt compares versions correctly" {
  run version_gt "2.0" "1.0"
  [ "$status" -eq 0 ]

  run version_gt "1.0" "2.0"
  [ "$status" -eq 1 ]
}

@test "version_ge compares versions correctly" {
  run version_ge "2.0" "1.0"
  [ "$status" -eq 0 ]

  run version_ge "1.0" "1.0"
  [ "$status" -eq 0 ]

  run version_ge "1.0" "2.0"
  [ "$status" -eq 1 ]
}

@test "version_lt compares versions correctly" {
  run version_lt "1.0" "2.0"
  [ "$status" -eq 0 ]

  run version_lt "2.0" "1.0"
  [ "$status" -eq 1 ]
}

@test "version_eq compares versions correctly" {
  run version_eq "1.0" "1.0"
  [ "$status" -eq 0 ]

  run version_eq "1.0" "2.0"
  [ "$status" -eq 1 ]
}

@test "command_exists detects existing commands" {
  run command_exists bash
  [ "$status" -eq 0 ]

  run command_exists nonexistent_command_12345
  [ "$status" -eq 1 ]
}

@test "shell_join joins array elements" {
  run shell_join "," "a" "b" "c"
  [ "$status" -eq 0 ]
  [ "$output" = "a,b,c" ]
}

@test "chomp removes trailing newline" {
  result=$(chomp "hello"$'\n')
  [ "$result" = "hello" ]
}

@test "is_ci detects CI environment" {
  unset CI
  unset GITHUB_ACTIONS
  unset GITLAB_CI

  run is_ci
  [ "$status" -eq 1 ]

  export CI=true
  run is_ci
  [ "$status" -eq 0 ]
}

@test "make_temp_dir creates temporary directory" {
  temp_dir=$(make_temp_dir)
  [ -d "$temp_dir" ]
  rm -rf "$temp_dir"
}
