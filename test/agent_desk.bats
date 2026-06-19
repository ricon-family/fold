#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load test_helper

setup() {
  TMPBIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$TMPBIN"
  export PATH="$TMPBIN:$PATH"
  export SHELL_LOG="$BATS_TEST_TMPDIR/shell.log"
  export SHELL_STATUS_MODE="ok"
  write_fake_shell
}

write_fake_shell() {
  cat > "$TMPBIN/shell" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'shell %s\n' "$*" >> "${SHELL_LOG:?}"
case "${1:-}" in
  status)
    if [ "${SHELL_STATUS_MODE:-ok}" = fail ]; then
      echo "not found"
      exit 1
    fi
    echo "running"
    ;;
  history)
    printf 'line one\nline two\nline three\n'
    ;;
  run)
    echo "${4:-}"
    ;;
  *)
    echo "unexpected shell command: $*" >&2
    exit 2
    ;;
esac
SH
  chmod +x "$TMPBIN/shell"
  export SHELL_BIN="$TMPBIN/shell"
}

make_repo() {
  local repo="$1" name="$2"
  mkdir -p "$repo"
  git init -q -b main "$repo"
  git -C "$repo" config user.name fixture
  git -C "$repo" config user.email fixture@example.test
  git -C "$repo" config commit.gpgsign false
  printf '%s\n' "$name" > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m "initial $name"
}

@test "agent:desk:status inspects one explicit desk without assuming singleton agent state" {
  desk="$BATS_TEST_TMPDIR/desks/quick-a"
  mkdir -p "$desk/.desk"
  printf '{"id":"quick-a"}\n' > "$desk/.desk/registry.json"
  make_repo "$desk/home" home
  make_repo "$desk/nvr" nvr
  desk_real=$(cd "$desk" && pwd -P)

  run fold_task agent:desk:status quick --desk "$desk" --shell quick-a --recent 1

  [ "$status" -eq 0 ]
  [[ "$output" == *"agent: quick"* ]]
  [[ "$output" == *"desk:  $desk_real"* ]]
  [[ "$output" == *"name: quick-a"* ]]
  [[ "$output" == *"running"* ]]
  [[ "$output" == *"== home =="* ]]
  [[ "$output" == *"== nvr =="* ]]
}

@test "agent:desk:pi-auth shows provider metadata without token values" {
  pi_dir="$BATS_TEST_TMPDIR/pi-agent"
  mkdir -p "$pi_dir"
  cat > "$pi_dir/auth.json" <<'JSON'
{
  "openai-codex": {
    "type": "SECRET_TYPE_VALUE",
    "access_token": "SECRET_ACCESS",
    "refresh": "SECRET_REFRESH",
    "accountId": "acct_123",
    "expires": 123
  },
  "huggingface": {
    "type": "api_key",
    "key": "SECRET_KEY"
  }
}
JSON
  cat > "$pi_dir/models.json" <<'JSON'
{"providers":{"openai-codex":{},"local-vllm":{}}}
JSON

  run fold_task agent:desk:pi-auth --pi-dir "$pi_dir"

  [ "$status" -eq 0 ]
  [[ "$output" == *"openai-codex"* ]]
  [[ "$output" == *"huggingface"* ]]
  [[ "$output" == *"provider_keys"* ]]
  [[ "$output" != *"SECRET_ACCESS"* ]]
  [[ "$output" != *"SECRET_REFRESH"* ]]
  [[ "$output" != *"SECRET_KEY"* ]]
  [[ "$output" != *"SECRET_TYPE_VALUE"* ]]
  [[ "$output" == *"type_key=present"* ]]
}

@test "agent:desk:smoke can fail closed when --check is set" {
  export SHELL_STATUS_MODE=fail

  run fold_task agent:desk:smoke --shell quick-missing --history-lines 2 --check

  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
  [[ "$output" == *"line two"* ]]
  [[ "$output" == *"line three"* ]]
}

@test "agent:desk:wake dry-run renders launcher without shell run" {
  home="$BATS_TEST_TMPDIR/home"
  work_dir="$BATS_TEST_TMPDIR/wake"
  packet="$BATS_TEST_TMPDIR/packet.md"
  make_repo "$home" home
  printf 'hello packet\n' > "$packet"

  run fold_task agent:desk:wake quick --home "$home" --shell quick-a --packet "$packet" --work-dir "$work_dir"

  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run"* ]]
  [ -x "$work_dir/start-quick-a.sh" ]
  if [ -f "$SHELL_LOG" ]; then
    ! grep -q 'shell run' "$SHELL_LOG"
  fi
  grep -q 'shimmer as "$AGENT"' "$work_dir/start-quick-a.sh"
}

@test "agent:desk:wake renders relative packet paths as absolute for the launcher" {
  home="$BATS_TEST_TMPDIR/home"
  work_dir="$BATS_TEST_TMPDIR/wake"
  make_repo "$home" home
  repo_real=$(cd "$REPO_DIR" && pwd -P)

  run fold_task agent:desk:wake quick --home "$home" --shell quick-a --packet AGENTS.md --work-dir "$work_dir"

  [ "$status" -eq 0 ]
  grep -q "PACKET_PATH='$repo_real/AGENTS.md'" "$work_dir/start-quick-a.sh"
}

@test "agent:desk:wake --yes launches shell and smokes it" {
  home="$BATS_TEST_TMPDIR/home"
  work_dir="$BATS_TEST_TMPDIR/wake"
  packet="$BATS_TEST_TMPDIR/packet.md"
  make_repo "$home" home
  printf 'hello packet\n' > "$packet"

  home_real=$(cd "$home" && pwd -P)
  work_real=$(cd "$work_dir" 2>/dev/null && pwd -P || printf '%s' "$work_dir")

  run fold_task agent:desk:wake quick --home "$home" --shell quick-a --packet "$packet" --work-dir "$work_dir" --yes

  [ "$status" -eq 0 ]
  [[ "$output" == *"launching shell quick-a"* ]]
  [[ "$output" == *"smoke:"* ]]
  work_real=$(cd "$work_dir" && pwd -P)
  grep -q "shell run --cwd $home_real quick-a $work_real/start-quick-a.sh" "$SHELL_LOG"
  grep -q "shell status quick-a" "$SHELL_LOG"
  grep -q "shell history quick-a" "$SHELL_LOG"
}
