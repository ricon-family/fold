#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load test_helper

write_passing_test() {
  local path="$1" name="$2"
  mkdir -p "$(dirname "$path")"
  local test_keyword='@test'
  printf '%s\n' \
    '#!/usr/bin/env bats' \
    "$test_keyword \"$name\" {" \
    '  true' \
    '}' > "$path"
}

@test "options-only calls use the configured Fold test directory and run all gates" {
  run fold_task test --jobs 1 \
    --filter '^agent:list preserves line-oriented CI roster$'

  [ "$status" -eq 0 ]
  [[ "$output" == *'ok 1 agent:list preserves line-oriented CI roster'* ]]
  [[ "$output" == *'== codebase lint =='* ]]
  [[ "$output" == *'== welcome smoke =='* ]]
}

@test "the bats mode uses the default target without running other gates" {
  run fold_task test bats --jobs 1 \
    --filter '^agent:list --json emits explicit GitHub logins$'

  [ "$status" -eq 0 ]
  [[ "$output" == *'ok 1 agent:list --json emits explicit GitHub logins'* ]]
  [[ "$output" != *'== codebase lint =='* ]]
  [[ "$output" != *'== welcome smoke =='* ]]
}

@test "the codebase mode runs only configured Codebase lints" {
  run fold_task test codebase

  [ "$status" -eq 0 ]
  [[ "$output" == *'== codebase lint =='* ]]
  [[ "$output" != *'== bats =='* ]]
  [[ "$output" != *'== welcome smoke =='* ]]
}

@test "an explicit test target takes precedence over the configured default" {
  local target="$BATS_TEST_TMPDIR/explicit.bats"
  write_passing_test "$target" 'explicit target only'

  run fold_task test bats --jobs 1 "$target"

  [ "$status" -eq 0 ]
  [[ "$output" == *'1..1'* ]]
  [[ "$output" == *'ok 1 explicit target only'* ]]
}

@test "relative test targets resolve from the repository root" {
  run fold_task test bats --jobs 1 test/agent_list.bats \
    --filter '^agent:list preserves line-oriented CI roster$'

  [ "$status" -eq 0 ]
  [[ "$output" == *'1..1'* ]]
  [[ "$output" == *'ok 1 agent:list preserves line-oriented CI roster'* ]]
}

@test "whitespace-bearing explicit test targets remain one argument" {
  local target="$BATS_TEST_TMPDIR/explicit target/passing test.bats"
  write_passing_test "$target" 'whitespace target'

  run fold_task test bats --jobs 2 "$target"

  [ "$status" -eq 0 ]
  [[ "$output" == *'1..1'* ]]
  [[ "$output" == *'ok 1 whitespace target'* ]]
}

@test "public Fold test path runs separate BATS files concurrently" {
  local probe_dir="$BATS_TEST_TMPDIR/across-file-probe"
  export PROBE_DIR="$BATS_TEST_TMPDIR/across-file-barrier"
  mkdir -p "$probe_dir" "$PROBE_DIR"
  local test_keyword='@test'

  for side in one two; do
    other=one
    [ "$side" = one ] && other=two
    cat > "$probe_dir/$side.bats" <<BATS
#!/usr/bin/env bats
$test_keyword "$side worker observes $other worker" {
  touch "\$PROBE_DIR/$side"
  for _ in {1..50}; do
    [ ! -e "\$PROBE_DIR/$other" ] || return 0
    sleep 0.05
  done
  false
}
BATS
  done

  run fold_task test bats "$probe_dir"

  [ "$status" -eq 0 ]
}

@test "public Fold test path keeps tests within one BATS file serial" {
  local target="$BATS_TEST_TMPDIR/within-file.bats"
  export PROBE_DIR="$BATS_TEST_TMPDIR/within-file-barrier"
  mkdir -p "$PROBE_DIR"
  local test_keyword='@test'

  cat > "$target" <<BATS
#!/usr/bin/env bats
$test_keyword "first test runs alone" {
  touch "\$PROBE_DIR/one"
  sleep 0.2
  [ ! -e "\$PROBE_DIR/two" ]
  rm "\$PROBE_DIR/one"
}
$test_keyword "second test runs alone" {
  touch "\$PROBE_DIR/two"
  sleep 0.2
  [ ! -e "\$PROBE_DIR/one" ]
  rm "\$PROBE_DIR/two"
}
BATS

  run fold_task test bats "$target"

  [ "$status" -eq 0 ]
}
