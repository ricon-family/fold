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
  write_setup_secrets_mock
}

write_setup_secrets_mock() {
  cat > "$TMPBIN/secrets" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" != "get" ]; then
  echo "unexpected secrets command: $*" >&2
  exit 2
fi
case "${2:-}" in
  test-agent/github-username) echo "test-agent-ricon" ;;
  *) echo "missing secret: ${2:-}" >&2; exit 1 ;;
esac
SH
  chmod +x "$TMPBIN/secrets"
  export SECRETS="$TMPBIN/secrets"
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
  local home="$1" prepare="${2:-true}" origin="${3:-https://github.com/test-agent-ricon/home.git}"
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
  if [ "$origin" != "none" ]; then
    git -C "$home" remote add origin "$origin"
  fi
}

create_plain_git_repo() {
  local repo="$1" origin="${2:-https://github.com/test-agent-ricon/home.git}"
  mkdir -p "$repo"
  git init -q -b main "$repo"
  printf '# not an agent home\n' > "$repo/README.md"
  git -C "$repo" add .
  git -C "$repo" \
    -c user.name="fixture" \
    -c user.email="fixture@example.test" \
    -c commit.gpgsign=false \
    commit -q -m "initial"
  if [ "$origin" != "none" ]; then
    git -C "$repo" remote add origin "$origin"
  fi
}

@test "homes:setup dry-run plans local setup without nested mutation" {
  home="$AGENTS_ROOT/test-agent/home"
  create_home_repo "$home"

  run fold_task homes:setup test-agent --agents-root "$AGENTS_ROOT" --home "$home"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Homes setup: test-agent"* ]]
  [[ "$output" == *"mode: dry-run"* ]]
  [[ "$output" == *"home repo"*"ok"* ]]
  [[ "$output" == *"home markers"*"AGENTS.md present"* ]]
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
  [[ "$output" == *"home markers"*"ok"* ]]
  [[ "$output" == *"home origin"*"test-agent-ricon/home"* ]]
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

@test "homes:setup --yes accepts a relocated correct home clone" {
  home="$BATS_TEST_TMPDIR/relocated-home"
  create_home_repo "$home" true "git@github.com:test-agent-ricon/home.git"

  run fold_task homes:setup test-agent --agents-root "$AGENTS_ROOT" --home "$home" --yes

  [ "$status" -eq 0 ]
  [[ "$output" == *"home: $home"* ]]
  [[ "$output" == *"home origin"*"test-agent-ricon/home"* ]]
  grep -F "PWD=$REPO_DIR ARGS=run -q homes:auth:setup test-agent --agents-root $AGENTS_ROOT --home $home --yes --json" "$FAKE_MISE_LOG"
}

@test "homes:setup --yes fails before nested mutation when home is missing" {
  home="$AGENTS_ROOT/test-agent/home"

  run fold_task homes:setup test-agent --agents-root "$AGENTS_ROOT" --home "$home" --yes

  [ "$status" -eq 1 ]
  [[ "$output" == *"home repo"*"fail"* ]]
  [[ "$output" == *"missing $home"* ]]
  [ ! -f "$FAKE_MISE_LOG" ]
}

@test "homes:setup --yes fails before nested mutation when AGENTS.md is missing" {
  home="$AGENTS_ROOT/test-agent/home"
  create_plain_git_repo "$home"

  run fold_task homes:setup test-agent --agents-root "$AGENTS_ROOT" --home "$home" --yes

  [ "$status" -eq 1 ]
  [[ "$output" == *"home markers"*"fail"* ]]
  [[ "$output" == *"missing AGENTS.md"* ]]
  [ ! -f "$FAKE_MISE_LOG" ]
}

@test "homes:setup --yes fails before nested mutation when origin is missing" {
  home="$AGENTS_ROOT/test-agent/home"
  create_home_repo "$home" true none

  run fold_task homes:setup test-agent --agents-root "$AGENTS_ROOT" --home "$home" --yes

  [ "$status" -eq 1 ]
  [[ "$output" == *"home origin"*"fail"* ]]
  [[ "$output" == *"missing origin remote"* ]]
  [[ "$output" == *"expected test-agent-ricon/home"* ]]
  [ ! -f "$FAKE_MISE_LOG" ]
}

@test "homes:setup --yes fails before nested mutation when origin belongs to another home" {
  home="$AGENTS_ROOT/test-agent/home"
  create_home_repo "$home" true "ssh://git@github.com/quick-ricon/home.git"

  run fold_task homes:setup test-agent --agents-root "$AGENTS_ROOT" --home "$home" --yes

  [ "$status" -eq 1 ]
  [[ "$output" == *"home origin"*"fail"* ]]
  [[ "$output" == *"expected test-agent-ricon/home"* ]]
  [[ "$output" == *"quick-ricon/home.git"* ]]
  [ ! -f "$FAKE_MISE_LOG" ]
}

@test "homes:setup --yes fails before nested mutation when origin is not a GitHub home remote" {
  home="$AGENTS_ROOT/test-agent/home"
  create_home_repo "$home" true "https://example.test/test-agent-ricon/home.git"

  run fold_task homes:setup test-agent --agents-root "$AGENTS_ROOT" --home "$home" --yes

  [ "$status" -eq 1 ]
  [[ "$output" == *"home origin"*"fail"* ]]
  [[ "$output" == *"expected test-agent-ricon/home"* ]]
  [[ "$output" == *"example.test"* ]]
  [ ! -f "$FAKE_MISE_LOG" ]
}
