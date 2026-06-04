#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load test_helper

setup() {
  TMPBIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$TMPBIN"
  export TMPBIN
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
