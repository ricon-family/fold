#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load test_helper

setup() {
  TMPBIN="$BATS_TEST_TMPDIR/bin"
  AGENTS_ROOT="$BATS_TEST_TMPDIR/agents"
  FAKE_MISE_LOG="$BATS_TEST_TMPDIR/mise.log"
  mkdir -p "$TMPBIN" "$AGENTS_ROOT"
  export TMPBIN AGENTS_ROOT FAKE_MISE_LOG
  write_nested_mise_mock
}

write_nested_mise_mock() {
  cat > "$TMPBIN/mise-nested" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'PWD=%s ARGS=%s\n' "$PWD" "$*" >> "${FAKE_MISE_LOG:?}"

case "$*" in
  run\ -q\ homes:auth:setup\ test-agent\ --agents-root\ *\ --home\ *\ --yes\ --json) exit 0 ;;
  trust) exit 0 ;;
  install) exit 0 ;;
  run\ -q\ agent:prepare) exit 0 ;;
  run\ -q\ homes:status\ test-agent\ --agents-root\ *\ --home\ *\ --json\ --check) exit 0 ;;
esac

echo "unexpected nested mise invocation: $*" >&2
exit 2
SH
  chmod +x "$TMPBIN/mise-nested"
  export MISE_BIN="$TMPBIN/mise-nested"
}

create_home_repo() {
  local home="$1" prepare="${2:-true}"
  mkdir -p "$home"
  git init -q -b main "$home"
  printf '# test-agent home\n' > "$home/AGENTS.md"
  if [ "$prepare" = "true" ]; then
    mkdir -p "$home/.mise/tasks/agent"
    cat > "$home/.mise/tasks/agent/prepare" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo prepare
SH
    chmod +x "$home/.mise/tasks/agent/prepare"
  fi
  git -C "$home" add .
  git -C "$home" \
    -c user.name="fixture" \
    -c user.email="fixture@example.test" \
    -c commit.gpgsign=false \
    commit -q -m "initial"
}

@test "homes:setup dry-run plans local setup without nested mutation" {
  home="$AGENTS_ROOT/test-agent/home"
  create_home_repo "$home"

  run fold_task homes:setup test-agent --agents-root "$AGENTS_ROOT" --home "$home"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Homes setup: test-agent"* ]]
  [[ "$output" == *"mode: dry-run"* ]]
  [[ "$output" == *"home repo"*"ok"* ]]
  [[ "$output" == *"auth setup"*"would run homes:auth:setup test-agent --yes"* ]]
  [[ "$output" == *"mise trust"*"would trust $home"* ]]
  [[ "$output" == *"agent:prepare"*"would run home prepare task"* ]]
  [[ "$output" == *"dry-run: rerun with --yes"* ]]
  [ ! -f "$FAKE_MISE_LOG" ]
}

@test "homes:setup --yes runs auth setup, home prepare, and final status" {
  home="$AGENTS_ROOT/test-agent/home"
  create_home_repo "$home"

  run fold_task homes:setup test-agent --agents-root "$AGENTS_ROOT" --home "$home" --yes

  [ "$status" -eq 0 ]
  [[ "$output" == *"mode: mutate"* ]]
  [[ "$output" == *"auth setup"*"ok"* ]]
  [[ "$output" == *"mise trust"*"ok"* ]]
  [[ "$output" == *"mise install"*"ok"* ]]
  [[ "$output" == *"agent:prepare"*"ok"* ]]
  [[ "$output" == *"status check"*"ok"* ]]
  [[ "$output" == *"next: cd $home && shimmer agent"* ]]

  grep -F "PWD=$REPO_DIR ARGS=run -q homes:auth:setup test-agent --agents-root $AGENTS_ROOT --home $home --yes --json" "$FAKE_MISE_LOG"
  grep -F "PWD=$home ARGS=trust" "$FAKE_MISE_LOG"
  grep -F "PWD=$home ARGS=install" "$FAKE_MISE_LOG"
  grep -F "PWD=$home ARGS=run -q agent:prepare" "$FAKE_MISE_LOG"
  grep -F "PWD=$REPO_DIR ARGS=run -q homes:status test-agent --agents-root $AGENTS_ROOT --home $home --json --check" "$FAKE_MISE_LOG"
}

@test "homes:setup --yes fails before nested mutation when home is missing" {
  home="$AGENTS_ROOT/test-agent/home"

  run fold_task homes:setup test-agent --agents-root "$AGENTS_ROOT" --home "$home" --yes

  [ "$status" -eq 1 ]
  [[ "$output" == *"home repo"*"fail"* ]]
  [[ "$output" == *"missing $home"* ]]
  [ ! -f "$FAKE_MISE_LOG" ]
}
