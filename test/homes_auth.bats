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
  write_homes_auth_mocks
}

assert_json_output() {
  printf '%s' "$output" | python3 -c 'import json, sys; json.load(sys.stdin)'
}

fold_task_stdout_only() {
  fold_task "$@" 2>"$BATS_TEST_TMPDIR/stderr"
}

write_homes_auth_mocks() {
  cat > "$TMPBIN/secrets" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" != "get" ]; then
  echo "unexpected secrets command: $*" >&2
  exit 2
fi
case "${2:-}" in
  test-agent/gpg-fingerprint) echo "ABCDEF1234567890ABCDEF1234567890ABCDEF12" ;;
  test-agent/gpg-private-key)
    cat <<'KEY'
-----BEGIN PGP FIXTURE KEY BLOCK-----
fixture-secret-material
-----END PGP FIXTURE KEY BLOCK-----
KEY
    ;;
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
last_arg=""
for arg in "$@"; do last_arg="$arg"; done

if has_arg "--list-secret-keys" "$@"; then
  if [ -f "${FAKE_GPG_STATE:?}" ]; then
    echo "sec   rsa4096/ABCDEF1234567890"
    exit 0
  fi
  exit 1
fi

if has_arg "--import" "$@" && has_arg "--dry-run" "$@"; then
  grep -q "BEGIN PGP" "$last_arg"
  exit 0
fi

if has_arg "--import" "$@"; then
  grep -q "BEGIN PGP" "$last_arg"
  if [ "${FAKE_GPG_IMPORT_FAIL:-false}" = "true" ]; then
    echo "import failed intentionally" >&2
    exit 42
  fi
  touch "${FAKE_GPG_STATE:?}"
  exit 0
fi

if has_arg "--edit-key" "$@"; then
  exit 0
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
  if [ "${GH_TOKEN:-}" = "fixture-github-token" ]; then
    if [ "${2:-}" = "/user" ]; then
      printf 'HTTP/2.0 200 OK\n'
      printf 'GitHub-Authentication-Token-Expiration: 2026-07-08 00:00:00 UTC\n'
      printf '\n'
      printf '{"login":"test-agent-ricon"}\n'
    else
      echo "${FAKE_GH_LOGIN:-test-agent-ricon}"
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

@test "homes includeIf helper preserves the existing default tilde key" {
  run bash -c 'source "$1"; homes_agent_include_key test-agent "$HOME/agents"' _ "$REPO_DIR/.mise/lib/homes.sh"

  [ "$status" -eq 0 ]
  [ "$output" = "includeIf.gitdir:~/agents/test-agent/.path" ]
}

@test "homes:auth reports ready when local auth is configured" {
  configure_ready_auth

  run fold_task homes:auth test-agent --agents-root "$AGENTS_ROOT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Homes auth: test-agent"* ]]
  [[ "$output" == *"# Secrets"* ]]
  [[ "$output" == *"# Signing"* ]]
  [[ "$output" == *"# GitHub"* ]]
  [[ "$output" == *"Git config"*"ok"* ]]
  [[ "$output" == *"GitHub token"*"valid as test-agent-ricon"* ]]
  [[ "$output" == *"expires in"* ]]
  [[ "$output" == *"# Next"* ]]
  [[ "$output" == *"auth ready"* ]]
  [[ "$output" != *"fixture-github-token"* ]]
}

@test "homes:auth --json reports missing local setup without leaking token" {
  run fold_task homes:auth test-agent --agents-root "$AGENTS_ROOT" --json

  [ "$status" -eq 0 ]
  [[ "$output" == *'"agent":"test-agent"'* ]]
  [[ "$output" == *'"ready":false'* ]]
  [[ "$output" == *'"name":"Secrets"'* ]]
  [[ "$output" == *'"name":"Signing"'* ]]
  [[ "$output" == *'"name":"GitHub"'* ]]
  assert_json_output
  [[ "$output" == *'"name":"Git config","status":"fail"'* ]]
  [[ "$output" == *"valid as test-agent-ricon; expires in"* ]]
  [[ "$output" == *"homes:auth:setup test-agent"* ]]
  [[ "$output" != *"Homes auth:"* ]]
  [[ "$output" != *"# Secrets"* ]]
  [[ "$output" != *"Checking:"* ]]
  [[ "$output" != *"fixture-github-token"* ]]
}

@test "homes:auth --json --check exits nonzero with clean JSON" {
  run fold_task_stdout_only homes:auth test-agent --agents-root "$AGENTS_ROOT" --json --check

  [ "$status" -eq 1 ]
  assert_json_output
  [[ "$output" == *'"ready":false'* ]]
  [[ "$output" == *"homes:auth:setup test-agent"* ]]
  [[ "$output" != *"Homes auth:"* ]]
  [[ "$output" != *"# Secrets"* ]]
  [[ "$output" != *"Checking:"* ]]
  [[ "$output" != *"fixture-github-token"* ]]
}

@test "homes:auth --check exits nonzero when auth is not ready" {
  run fold_task homes:auth test-agent --agents-root "$AGENTS_ROOT" --check

  [ "$status" -eq 1 ]
  [[ "$output" == *"# Next"* ]]
  [[ "$output" == *"homes:auth:setup test-agent"* ]]
  [[ "$output" != *"fixture-github-token"* ]]
}


@test "homes:auth:setup dry-run does not import or write local config" {
  run fold_task homes:auth:setup test-agent --agents-root "$AGENTS_ROOT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"mode: dry-run"* ]]
  [[ "$output" == *"would import existing private key"* ]]
  [[ "$output" == *"dry-run: rerun with --yes"* ]]
  [ ! -f "$FAKE_GPG_STATE" ]
  [ ! -f "$AGENTS_ROOT/test-agent/.gitconfig" ]
  [ ! -s "$GIT_CONFIG_GLOBAL" ]
  [[ "$output" != *"fixture-github-token"* ]]
  [[ "$output" != *"PGP FIXTURE KEY"* ]]
}

@test "homes:auth:setup --yes validates GitHub before mutating local auth" {
  export FAKE_GH_LOGIN="wrong-agent"

  run fold_task homes:auth:setup test-agent --agents-root "$AGENTS_ROOT" --yes

  [ "$status" -eq 1 ]
  [ ! -f "$FAKE_GPG_STATE" ]
  [ ! -f "$AGENTS_ROOT/test-agent/.gitconfig" ]
  [ ! -s "$GIT_CONFIG_GLOBAL" ]
  [[ "$output" == *"GitHub token login mismatch"* ]]
  [[ "$output" != *"fixture-github-token"* ]]
  [[ "$output" != *"PGP FIXTURE KEY"* ]]
}

@test "homes:auth:setup --yes removes temporary private key file when import fails" {
  import_tmp="$BATS_TEST_TMPDIR/import-tmp"
  mkdir -p "$import_tmp"
  export TMPDIR="$import_tmp"
  export FAKE_GPG_IMPORT_FAIL=true

  run fold_task homes:auth:setup test-agent --agents-root "$AGENTS_ROOT" --yes

  [ "$status" -eq 1 ]
  [ ! -f "$FAKE_GPG_STATE" ]
  [ -z "$(find "$import_tmp" -type f -print -quit)" ]
  [[ "$output" == *"GPG import failed"* ]]
  [[ "$output" != *"fixture-secret-material"* ]]
  [[ "$output" != *"PGP FIXTURE KEY"* ]]
}

@test "homes:auth:setup --yes imports key, writes gitconfig, and configures includeIf" {
  run fold_task homes:auth:setup test-agent --agents-root "$AGENTS_ROOT" --yes

  [ "$status" -eq 0 ]
  [ -f "$FAKE_GPG_STATE" ]
  [ -f "$AGENTS_ROOT/test-agent/.gitconfig" ]
  [ "$(git config --file "$AGENTS_ROOT/test-agent/.gitconfig" user.name)" = "test-agent" ]
  [ "$(git config --file "$AGENTS_ROOT/test-agent/.gitconfig" user.email)" = "test-agent@ricon.family" ]
  [ "$(git config --file "$AGENTS_ROOT/test-agent/.gitconfig" user.signingkey)" = "ABCDEF1234567890ABCDEF1234567890ABCDEF12" ]
  [ "$(git config --file "$AGENTS_ROOT/test-agent/.gitconfig" commit.gpgsign)" = "true" ]
  git config --global --get-all "includeIf.gitdir:$AGENTS_ROOT/test-agent/.path" | grep -Fx "$AGENTS_ROOT/test-agent/.gitconfig"
  [[ "$output" == *"github token"*"valid as test-agent-ricon"* ]]
  [[ "$output" != *"fixture-github-token"* ]]
  [[ "$output" != *"PGP FIXTURE KEY"* ]]

  run fold_task homes:auth test-agent --agents-root "$AGENTS_ROOT" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ready":true'* ]]
  [[ "$output" == *"valid as test-agent-ricon; expires in"* ]]
}
