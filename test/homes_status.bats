#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load test_helper

setup() {
  TMPBIN="$BATS_TEST_TMPDIR/bin"
  AGENTS_ROOT="$BATS_TEST_TMPDIR/agents"
  FAKE_GPG_STATE="$BATS_TEST_TMPDIR/gpg-secret-imported"
  FAKE_GH_LOG="$BATS_TEST_TMPDIR/gh.log"
  mkdir -p "$TMPBIN" "$AGENTS_ROOT"
  export TMPBIN AGENTS_ROOT FAKE_GPG_STATE FAKE_GH_LOG
  export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/global.gitconfig"
  : > "$GIT_CONFIG_GLOBAL"
  write_homes_status_mocks
}

assert_json_output() {
  printf '%s' "$output" | python3 -c 'import json, sys; json.load(sys.stdin)'
}

fold_task_stdout_only() {
  fold_task "$@" 2>"$BATS_TEST_TMPDIR/stderr"
}

write_homes_status_mocks() {
  cat > "$TMPBIN/secrets" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" != "get" ]; then
  echo "unexpected secrets command: $*" >&2
  exit 2
fi
case "${2:-}" in
  test-agent/gpg-fingerprint) echo "ABCDEF1234567890ABCDEF1234567890ABCDEF12" ;;
  test-agent/gpg-private-key) echo "fixture-secret-material" ;;
  test-agent/github-username) echo "test-agent-ricon" ;;
  test-agent/github-pat) echo "fixture-github-token" ;;
  *) echo "missing secret: ${2:-}" >&2; exit 1 ;;
esac
SH
  chmod +x "$TMPBIN/secrets"
  export SECRETS="$TMPBIN/secrets"

  cat > "$TMPBIN/gpg" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
has_arg() {
  local wanted="$1" arg
  shift
  for arg in "$@"; do
    [ "$arg" = "$wanted" ] && return 0
  done
  return 1
}
if has_arg "--list-secret-keys" "$@"; then
  if [ -f "${FAKE_GPG_STATE:?}" ]; then
    echo "sec   rsa4096/ABCDEF1234567890"
    exit 0
  fi
  exit 1
fi

echo "unexpected gpg command: $*" >&2
exit 2
SH
  chmod +x "$TMPBIN/gpg"
  export GPG="$TMPBIN/gpg"

  cat > "$TMPBIN/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'GH_TOKEN=%s ARGS=%s\n' "${GH_TOKEN:+set}" "$*" >> "${FAKE_GH_LOG:?}"
if [ "${1:-}" = "api" ] && { [ "${2:-}" = "user" ] || [ "${2:-}" = "/user" ]; }; then
  if [ -n "${FAKE_GH_SLEEP:-}" ]; then
    sleep "$FAKE_GH_SLEEP"
  fi
  if [ "${GH_TOKEN:-}" = "fixture-github-token" ]; then
    if [ "${2:-}" = "/user" ]; then
      printf 'HTTP/2.0 200 OK\n\n'
      printf '{"login":"test-agent-ricon"}\n'
    else
      echo "test-agent-ricon"
    fi
    exit 0
  fi
  echo "Bad credentials" >&2
  exit 1
fi

echo "unexpected gh command: $*" >&2
exit 2
SH
  chmod +x "$TMPBIN/gh"
  export GH="$TMPBIN/gh"

  cat > "$TMPBIN/notes" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "changes" ] && [ "${2:-}" = "--summary" ]; then
  echo "No changes."
  exit 0
fi
echo "unexpected notes command: $*" >&2
exit 2
SH
  chmod +x "$TMPBIN/notes"
  export NOTES="$TMPBIN/notes"

  cat > "$TMPBIN/modules" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
exit 0
SH
  chmod +x "$TMPBIN/modules"
  export MODULES="$TMPBIN/modules"
}

configure_ready_auth() {
  mkdir -p "$AGENTS_ROOT/test-agent"
  cat > "$AGENTS_ROOT/test-agent/.gitconfig" <<'GITCONFIG'
[user]
	name = test-agent
	email = test-agent@ricon.family
	signingkey = ABCDEF1234567890ABCDEF1234567890ABCDEF12
[commit]
	gpgsign = true
[tag]
	gpgsign = true
GITCONFIG
  touch "$FAKE_GPG_STATE"
  git config --global --add "includeIf.gitdir:$AGENTS_ROOT/test-agent/.path" "$AGENTS_ROOT/test-agent/.gitconfig"
}

create_module_clone() {
  local module_dir="$1"
  mkdir -p "$module_dir"
  git init -q -b main "$module_dir"
  git -C "$module_dir" config user.name "fixture"
  git -C "$module_dir" config user.email "fixture@example.test"
  git -C "$module_dir" config commit.gpgsign false
  printf 'module fixture\n' > "$module_dir/README.md"
  git -C "$module_dir" add README.md
  git -C "$module_dir" commit -q -m "initial module"
  git -C "$module_dir" rev-parse HEAD
}

create_ready_home() {
  local home="$1" fold_pin den_pin
  mkdir -p "$home/.mise/tasks/agent" "$home/notes" "$home/.modules" "$home/modules"
  git init -q -b main "$home"

  cat > "$home/AGENTS.md" <<'MD'
# test-agent home
MD
  cat > "$home/mise.toml" <<'TOML'
[settings]
quiet = true

[tools]
"shiv:notes" = "0.8"
"shiv:modules" = "0.9"
TOML
  cat > "$home/.mise/tasks/agent/prepare" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo prepare
SH
  chmod +x "$home/.mise/tasks/agent/prepare"
  printf 'modules/\n' > "$home/.gitignore"
  printf 'fake notes manifest\n' > "$home/notes/.manifest"

  fold_pin=$(create_module_clone "$home/modules/fold")
  den_pin=$(create_module_clone "$home/modules/den")
  printf 'fold\thttps://github.com/ricon-family/fold.git\t%s\tmain\n' "$fold_pin" > "$home/.modules/manifest"
  printf 'den\thttps://github.com/ricon-family/den.git\t%s\tmain\n' "$den_pin" >> "$home/.modules/manifest"

  git -C "$home" remote add origin "https://github.com/test-agent/home.git"
  git -C "$home" add AGENTS.md mise.toml .mise notes/.manifest .modules/manifest .gitignore
  git -C "$home" \
    -c user.name="fixture" \
    -c user.email="fixture@example.test" \
    -c commit.gpgsign=false \
    commit -q -m "initial"
}

advance_module_to_tracked_main() {
  local module_dir="$1" remote="$2"
  git clone -q --bare "$module_dir" "$remote"
  git -C "$module_dir" remote add origin "$remote"
  printf '\ntracked update\n' >> "$module_dir/README.md"
  git -C "$module_dir" add README.md
  git -C "$module_dir" commit -q -m "advance tracked module"
  git -C "$module_dir" push -q origin main
}

add_prepare_modules_and_optional_or_home() {
  local home="$1"
  cat >> "$home/mise.toml" <<'TOML'

[env]
AGENT_PREPARE_MODULES = "den fold"
TOML
  printf 'or-home\thttps://github.com/rikonor/home.git\t1111111111111111111111111111111111111111\tmain\n' >> "$home/.modules/manifest"
  git -C "$home" add mise.toml .modules/manifest
  git -C "$home" \
    -c user.name="fixture" \
    -c user.email="fixture@example.test" \
    -c commit.gpgsign=false \
    commit -q -m "configure prepare modules"
}

@test "homes:status reports a ready configured home" {
  home="$AGENTS_ROOT/test-agent/home"
  create_ready_home "$home"
  configure_ready_auth

  run fold_task homes:status test-agent --agents-root "$AGENTS_ROOT" --home "$home"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Homes status: test-agent"* ]]
  [[ "$output" == *"# Summary"* ]]
  [[ "$output" == *"Auth"*"ready"* ]]
  [[ "$output" == *"Home"*"clean main @"* ]]
  [[ "$output" == *"Notes"*"clean"* ]]
  [[ "$output" == *"Modules"*"2 required module(s) ready"* ]]
  [[ "$output" != *"# Auth: Secrets"* ]]
  [[ "$output" != *"module:fold"* ]]
  [[ "$output" == *"home ready"* ]]
  [[ "$output" != *"fixture-github-token"* ]]
  [[ "$output" != *"fixture-secret-material"* ]]
}

@test "homes:status accepts tracked modules and skips modules outside AGENT_PREPARE_MODULES" {
  home="$AGENTS_ROOT/test-agent/home"
  create_ready_home "$home"
  configure_ready_auth
  advance_module_to_tracked_main "$home/modules/fold" "$BATS_TEST_TMPDIR/fold.git"
  add_prepare_modules_and_optional_or_home "$home"

  run fold_task_stdout_only homes:status test-agent --agents-root "$AGENTS_ROOT" --home "$home" --json --check

  [ "$status" -eq 0 ]
  assert_json_output
  [[ "$output" == *'"ready":true'* ]]
  [[ "$output" == *'"name":"Prepare modules","status":"ok","detail":"AGENT_PREPARE_MODULES=den fold"'* ]]
  [[ "$output" == *'"name":"module:fold","status":"ok","detail":"tracking main at '* ]]
  [[ "$output" == *'"name":"optional:or-home","status":"ok","detail":"not required by AGENT_PREPARE_MODULES"'* ]]
  [[ "$output" != *'"status":"fail"'* ]]
}

@test "homes:status --json --check emits clean ready JSON" {
  home="$AGENTS_ROOT/test-agent/home"
  create_ready_home "$home"
  configure_ready_auth

  run fold_task homes:status test-agent --agents-root "$AGENTS_ROOT" --home "$home" --json --check

  [ "$status" -eq 0 ]
  assert_json_output
  [[ "$output" == *'"agent":"test-agent"'* ]]
  [[ "$output" == *'"ready":true'* ]]
  [[ "$output" == *'"name":"Auth: Secrets"'* ]]
  [[ "$output" == *'"name":"Auth: Signing"'* ]]
  [[ "$output" == *'"name":"Modules"'* ]]
  [[ "$output" != *"Homes status:"* ]]
  [[ "$output" != *"# Auth"* ]]
  [[ "$output" != *"fixture-github-token"* ]]
}

@test "homes:status --json --check exits nonzero when auth is not ready" {
  home="$AGENTS_ROOT/test-agent/home"
  create_ready_home "$home"

  run fold_task_stdout_only homes:status test-agent --agents-root "$AGENTS_ROOT" --home "$home" --json --check

  [ "$status" -eq 1 ]
  assert_json_output
  [[ "$output" == *'"ready":false'* ]]
  [[ "$output" == *"homes:auth:setup test-agent"* ]]
  [[ "$output" == *'"name":"Auth: Signing"'* ]]
  [[ "$output" == *'"name":"GPG secret key","status":"fail"'* ]]
  [[ "$output" != *"Homes status:"* ]]
  [[ "$output" != *"# Auth"* ]]
  [[ "$output" != *"fixture-github-token"* ]]
  [[ "$output" != *"fixture-secret-material"* ]]
}

@test "homes:status points missing homes at adopt-remote when auth is ready" {
  configure_ready_auth

  run fold_task_stdout_only homes:status test-agent \
    --agents-root "$AGENTS_ROOT" \
    --home "$AGENTS_ROOT/test-agent/home" \
    --json \
    --check

  [ "$status" -eq 1 ]
  assert_json_output
  [[ "$output" == *'"ready":false'* ]]
  [[ "$output" == *'"name":"Home path","status":"fail"'* ]]
  [[ "$output" == *"homes:adopt-remote test-agent"* ]]
  [[ "$output" != *"fixture-github-token"* ]]
}

@test "homes:status reports auth timeout instead of hanging" {
  command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1 || skip "timeout/gtimeout command unavailable"
  home="$AGENTS_ROOT/test-agent/home"
  create_ready_home "$home"
  configure_ready_auth
  export FAKE_GH_SLEEP=5
  export HOMES_STATUS_AUTH_TIMEOUT=1

  run fold_task_stdout_only homes:status test-agent --agents-root "$AGENTS_ROOT" --home "$home" --json --check

  [ "$status" -eq 1 ]
  assert_json_output
  [[ "$output" == *'"ready":false'* ]]
  [[ "$output" == *'"name":"homes:auth","status":"fail","detail":"timed out after 1s"'* ]]
  [[ "$output" == *"mise run homes:auth test-agent"* ]]
  [[ "$output" != *"fixture-github-token"* ]]
}
