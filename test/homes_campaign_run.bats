#!/usr/bin/env bats

load test_helper

setup() {
  TEST_TMPDIR=$(mktemp -d)
  export TEST_TMPDIR

  STATE_DIR="$TEST_TMPDIR/state"
  mkdir -p "$STATE_DIR/clones/one/.git" "$STATE_DIR/clones/two/.git"

  cat > "$STATE_DIR/targets.tsv" <<TSV
repo	auth	clone	branch	base
owner/one	-	$STATE_DIR/clones/one	campaign/test	main
owner/two	-	$STATE_DIR/clones/two	campaign/test	main
TSV

  RUN_LOG="$TEST_TMPDIR/run.log"
  export RUN_LOG
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

@test "homes:campaign:run runs a command in every target clone" {
  run fold_task homes:campaign:run \
    --work-dir "$STATE_DIR" \
    -- bash -c 'printf "%s\n" "$PWD" >> "$RUN_LOG"'

  [ "$status" -eq 0 ]
  grep -Fx "$STATE_DIR/clones/one" "$RUN_LOG"
  grep -Fx "$STATE_DIR/clones/two" "$RUN_LOG"
  [[ "$output" == *"== owner/one =="* ]]
  [[ "$output" == *"== owner/two =="* ]]
}

@test "homes:campaign:run filters by repo" {
  run fold_task homes:campaign:run \
    --work-dir "$STATE_DIR" \
    --repo owner/two \
    -- bash -c 'touch ran'

  [ "$status" -eq 0 ]
  [ ! -e "$STATE_DIR/clones/one/ran" ]
  [ -e "$STATE_DIR/clones/two/ran" ]
  [[ "$output" != *"== owner/one =="* ]]
  [[ "$output" == *"== owner/two =="* ]]
}

@test "homes:campaign:run fails when no command is provided" {
  run fold_task homes:campaign:run --work-dir "$STATE_DIR"

  [ "$status" -ne 0 ]
  [[ "$output" == *"provide a command after --"* ]]
}

@test "homes:campaign:run returns nonzero if a target command fails" {
  run fold_task homes:campaign:run \
    --work-dir "$STATE_DIR" \
    --repo owner/one \
    -- bash -c 'exit 7'

  [ "$status" -ne 0 ]
  [[ "$output" == *"== owner/one =="* ]]
}

@test "homes:campaign:run keep-going runs remaining targets after failures" {
  run fold_task homes:campaign:run \
    --work-dir "$STATE_DIR" \
    --keep-going \
    -- bash -c 'printf "%s\n" "$PWD" >> "$RUN_LOG"; [ "${PWD##*/}" = two ]'

  [ "$status" -ne 0 ]
  grep -Fx "$STATE_DIR/clones/one" "$RUN_LOG"
  grep -Fx "$STATE_DIR/clones/two" "$RUN_LOG"
}
