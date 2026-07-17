#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load test_helper

setup() {
  TMPBIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$TMPBIN"
  export TMPBIN
}

setup_bats_mocks() {
  BATS_LOG="$BATS_TEST_TMPDIR/bats.log"
  export BATS_LOG

  cat > "$TMPBIN/bats" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
{
  printf 'jobs=%s\n' "${BATS_NUMBER_OF_PARALLEL_JOBS:-}"
  printf 'runner=%s\n' "${BATS_PARALLEL_BINARY_NAME:-}"
  for arg in "$@"; do
    printf 'arg=%s\n' "$arg"
  done
} > "$BATS_LOG"
BASH

  cat > "$TMPBIN/rush" <<'BASH'
#!/usr/bin/env bash
exit 0
BASH

  chmod +x "$TMPBIN/bats" "$TMPBIN/rush"
  export BATS_COMMAND="$TMPBIN/bats"
  export RUSH_COMMAND="$TMPBIN/rush"
  unset BATS_NUMBER_OF_PARALLEL_JOBS BATS_PARALLEL_BINARY_NAME
}

log_value() {
  local key="$1"
  awk -F= -v key="$key" '$1 == key { print substr($0, length(key) + 2); exit }' "$BATS_LOG"
}

arg_count() {
  local expected="$1"
  awk -F= -v expected="$expected" '$1 == "arg" && substr($0, 5) == expected { count++ } END { print count + 0 }' "$BATS_LOG"
}

@test "test codebase runs configured codebase lints" {
  cat > "$TMPBIN/codebase" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/codebase-args"
printf 'codebase ok: %s\n' "$1"
EOF
  chmod +x "$TMPBIN/codebase"

  export CODEBASE_BIN="$TMPBIN/codebase"
  run fold_task test codebase

  [ "$status" -eq 0 ]
  grep -q "^lint$" "$BATS_TEST_TMPDIR/codebase-args"
}

@test "test bats defaults to four Rush jobs across files" {
  setup_bats_mocks

  run fold_task test bats agent_list --filter json
  [ "$status" -eq 0 ]
  [[ "$output" == *"4 jobs across files"* ]]
  [[ "$output" != *"codebase lint"* ]]
  [[ "$output" != *"welcome smoke"* ]]
  [ "$(log_value jobs)" = "4" ]
  [ "$(log_value runner)" = "$TMPBIN/rush" ]
  [ "$(arg_count --no-parallelize-within-files)" -eq 1 ]
  [ "$(arg_count "$REPO_DIR/test/agent_list.bats")" -eq 1 ]
  [ "$(arg_count --filter)" -eq 1 ]
  [ "$(arg_count json)" -eq 1 ]
}

@test "explicit BATS jobs override is forwarded once" {
  setup_bats_mocks

  run fold_task test bats --jobs 3 agent_list
  [ "$status" -eq 0 ]
  [[ "$output" == *"3 jobs across files"* ]]
  [ "$(log_value jobs)" = "" ]
  [ "$(arg_count --jobs)" -eq 1 ]
  [ "$(arg_count 3)" -eq 1 ]
  [ "$(arg_count --no-parallelize-within-files)" -eq 1 ]
}

@test "BATS environment jobs override the default" {
  setup_bats_mocks
  export BATS_NUMBER_OF_PARALLEL_JOBS=2

  run fold_task test bats agent_list
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 jobs across files"* ]]
  [ "$(log_value jobs)" = "2" ]
  [ "$(arg_count --jobs)" -eq 0 ]
}

@test "BATS environment serial opt-out does not require Rush" {
  setup_bats_mocks
  export BATS_NUMBER_OF_PARALLEL_JOBS=1
  export RUSH_COMMAND="$TMPBIN/missing-rush"

  run fold_task test bats agent_list
  [ "$status" -eq 0 ]
  [[ "$output" == *"BATS parallelism: serial"* ]]
  [ "$(arg_count --no-parallelize-within-files)" -eq 0 ]
}

@test "BATS CLI serial opt-out does not require Rush" {
  setup_bats_mocks
  export RUSH_COMMAND="$TMPBIN/missing-rush"

  run fold_task test bats --jobs 1 agent_list
  [ "$status" -eq 0 ]
  [[ "$output" == *"BATS parallelism: serial"* ]]
  [ "$(arg_count --no-parallelize-within-files)" -eq 0 ]
}

@test "parallel BATS fails clearly when Rush is unavailable" {
  setup_bats_mocks
  export RUSH_COMMAND="$TMPBIN/missing-rush"

  run -127 fold_task test bats agent_list
  [ "$status" -eq 127 ]
  [[ "$output" == *"parallel runner '$TMPBIN/missing-rush' is unavailable for 4 jobs"* ]]
  [[ "$output" == *"run 'mise install' or use --jobs 1"* ]]
  [ ! -e "$BATS_LOG" ]
}

@test "explicit BATS runner override is preserved" {
  setup_bats_mocks
  cp "$TMPBIN/rush" "$TMPBIN/alternate-runner"
  export BATS_PARALLEL_BINARY_NAME="$TMPBIN/alternate-runner"

  run fold_task test bats agent_list
  [ "$status" -eq 0 ]
  [ "$(log_value runner)" = "$TMPBIN/alternate-runner" ]
}

@test "invalid BATS job override fails before execution" {
  setup_bats_mocks
  export BATS_NUMBER_OF_PARALLEL_JOBS=lots

  run fold_task test bats agent_list
  [ "$status" -eq 2 ]
  [[ "$output" == *"must be a positive integer"* ]]
  [ ! -e "$BATS_LOG" ]
}
