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
  export AGENT_HOME="$AGENTS_ROOT/test-agent/home"
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
if [ -n "${FAKE_SECRET_LOG:-}" ]; then
  printf '%s\n' "${2:-}" >> "$FAKE_SECRET_LOG"
fi
if [ "${2:-}" = "${FAKE_MISSING_GIT_FIELD:-}" ]; then
  exit 1
fi
case "${2:-}" in
  test-agent/git/name) printf '%s\n' "${FAKE_GIT_NAME-Persona Author}" ;;
  test-agent/git/email) printf '%s\n' "${FAKE_GIT_EMAIL-commits@example.test}" ;;
  test-agent/git/signing-fingerprint) echo "ABCDEF1234567890ABCDEF1234567890ABCDEF12" ;;
  test-agent/gpg-private-key)
    cat <<'KEY'
-----BEGIN PGP FIXTURE KEY BLOCK-----
fixture-secret-material
-----END PGP FIXTURE KEY BLOCK-----
KEY
    ;;
  test-agent/github-username) echo "test-agent-ricon" ;;
  test-agent/github/token) echo "fixture-github-token" ;;
  *) echo "missing secret: ${2:-}" >&2; exit 1 ;;
esac
SH
  chmod +x "$TMPBIN/secrets"
  export SECRETS="$TMPBIN/secrets"

  cat > "$TMPBIN/gpg" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ -n "${FAKE_GPG_LOG:-}" ]; then
  printf '%s\n' "$*" >> "$FAKE_GPG_LOG"
fi
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
  if [ "${FAKE_GPG_DRY_RUN_FAIL:-false}" = "true" ]; then
    echo "parse failed intentionally: fixture-secret-material" >&2
    exit 43
  fi
  exit 0
fi

if has_arg "--import" "$@"; then
  grep -q "BEGIN PGP" "$last_arg"
  if [ "${FAKE_GPG_IMPORT_FAIL:-false}" = "true" ]; then
    echo "import failed intentionally: fixture-secret-material" >&2
    exit 42
  fi
  touch "${FAKE_GPG_STATE:?}"
  exit 0
fi

if has_arg "--edit-key" "$@"; then
  printf '%s\n' "$@" > "${FAKE_GPG_STATE:?}.trust"
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
	name = Persona Author
	email = commits@example.test
	signingkey = ABCDEF1234567890ABCDEF1234567890ABCDEF12
[commit]
	gpgsign = true
[tag]
	gpgsign = true
GITCONFIG
  touch "$FAKE_GPG_STATE"
  git config --global --add "includeIf.gitdir:$AGENTS_ROOT/test-agent/.path" "$AGENTS_ROOT/test-agent/.gitconfig"
}

configure_auth_prerequisites() {
  unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS GIT_CONFIG
  git config --global user.name 'Persona Author'
  git config --global user.email commits@example.test
  git config --global user.signingkey ABCDEF1234567890ABCDEF1234567890ABCDEF12
  git config --global gpg.format openpgp
  git config --global commit.gpgsign true
  git config --global tag.gpgsign true
  touch "$FAKE_GPG_STATE"
  export FAKE_SECRET_LOG="$BATS_TEST_TMPDIR/secret-requests"
  export FAKE_GPG_LOG="$BATS_TEST_TMPDIR/gpg-requests"
}

@test "homes:auth prerequisites accept account defaults without retrieving private key material or changing auth" {
  configure_auth_prerequisites
  export FAKE_MISSING_GIT_FIELD=test-agent/gpg-private-key
  cp "$GIT_CONFIG_GLOBAL" "$BATS_TEST_TMPDIR/before.gitconfig"

  run fold_task_stdout_only homes:auth test-agent --home "$AGENTS_ROOT/new/home" --prerequisites --json --check

  [ "$status" -eq 0 ]
  assert_json_output
  [[ "$output" == *'"ready":true'* ]]
  ! grep -q 'gpg-private-key' "$FAKE_SECRET_LOG"
  ! grep -Eq -- '--import|--edit-key|--sign' "$FAKE_GPG_LOG"
  [ ! -e "$FAKE_GPG_STATE.trust" ]
  [ ! -e "$AGENTS_ROOT/new" ]
  cmp -s "$GIT_CONFIG_GLOBAL" "$BATS_TEST_TMPDIR/before.gitconfig"
  [[ "$output" != *'fixture-github-token'* ]]
}

@test "homes:auth prerequisites refuse a missing local signer without importing or trusting it" {
  configure_auth_prerequisites
  rm "$FAKE_GPG_STATE"
  cp "$GIT_CONFIG_GLOBAL" "$BATS_TEST_TMPDIR/before.gitconfig"

  run fold_task_stdout_only homes:auth test-agent --prerequisites --json --check

  [ "$status" -eq 1 ]
  assert_json_output
  [[ "$output" == *'missing for stored fingerprint'* ]]
  [[ "$output" != *'homes:auth:setup'* ]]
  [ ! -e "$FAKE_GPG_STATE" ]
  [ ! -e "$FAKE_GPG_STATE.trust" ]
  ! grep -Eq -- '--import|--edit-key|--sign' "$FAKE_GPG_LOG"
  cmp -s "$GIT_CONFIG_GLOBAL" "$BATS_TEST_TMPDIR/before.gitconfig"
}

@test "homes:auth prerequisites require every persona Git setting" {
  configure_auth_prerequisites

  for key in user.name user.email user.signingkey gpg.format commit.gpgsign tag.gpgsign; do
    expected=$(git config --global --get "$key")
    git config --global "$key" wrong-value

    run fold_task_stdout_only homes:auth test-agent --prerequisites --json --check

    [ "$status" -eq 1 ]
    [[ "$output" == *"\"name\":\"Git $key\",\"status\":\"fail\""* ]]
    [ "$(git config --global --get "$key")" = wrong-value ]
    git config --global "$key" "$expected"
  done
}

@test "homes:auth prerequisites inspect the existing target home's effective Git settings" {
  configure_auth_prerequisites
  home="$AGENTS_ROOT/new/home"
  mkdir -p "$home"
  git init -q "$home"
  git -C "$home" config user.name Other

  run fold_task_stdout_only homes:auth test-agent --home "$home" --prerequisites --json --check

  [ "$status" -eq 1 ]
  [[ "$output" == *'"name":"Git user.name","status":"fail"'* ]]
  [ "$(git -C "$home" config user.name)" = Other ]
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


@test "homes:auth:setup previews AGENT_HOME without secrets, network, GPG, or config writes" {
  export FAKE_SECRET_LOG="$BATS_TEST_TMPDIR/secrets.log"
  export FAKE_GPG_LOG="$BATS_TEST_TMPDIR/gpg.log"
  run fold_task homes:auth:setup test-agent --agents-root "$AGENTS_ROOT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"home: $AGENT_HOME"* ]]
  [[ "$output" == *"mode: dry-run"* ]]
  [[ "$output" == *"would import existing private key"* ]]
  [ ! -e "$FAKE_SECRET_LOG" ]
  [ ! -e "$FAKE_GPG_LOG" ]
  [ ! -e "$FAKE_GH_LOG" ]
  [[ "$output" == *"dry-run: rerun with --yes"* ]]
  [ ! -f "$FAKE_GPG_STATE" ]
  [ ! -f "$AGENTS_ROOT/test-agent/.gitconfig" ]
  [ ! -s "$GIT_CONFIG_GLOBAL" ]
  [[ "$output" != *"fixture-github-token"* ]]
  [[ "$output" != *"PGP FIXTURE KEY"* ]]
}

@test "homes:auth:setup emits a JSON plan for an explicit home without accessing auth" {
  target="$BATS_TEST_TMPDIR/selected desk/home"
  export SECRETS=/usr/bin/false GPG=/usr/bin/false GH=/usr/bin/false

  run fold_task homes:auth:setup test-agent --home "$target" --json

  [ "$status" -eq 0 ]
  assert_json_output
  printf '%s' "$output" | jq -e --arg home "$target" \
    '.home == $home and .mode == "dry-run" and all(.actions[]; .status == "plan")'
  [ ! -e "$target" ]
  [ ! -s "$GIT_CONFIG_GLOBAL" ]
  [ ! -e "$FAKE_GH_LOG" ]
}

@test "homes:auth:setup --yes does not leak private key data when parse fails" {
  parse_tmp="$BATS_TEST_TMPDIR/parse-tmp"
  mkdir -p "$parse_tmp"
  export TMPDIR="$parse_tmp"
  export FAKE_GPG_DRY_RUN_FAIL=true

  run fold_task homes:auth:setup test-agent --agents-root "$AGENTS_ROOT" --yes

  [ "$status" -eq 1 ]
  [ -z "$(find "$parse_tmp" -type f -print -quit)" ]
  [[ "$output" == *"GPG cannot parse key"* ]]
  [[ "$output" != *"fixture-secret-material"* ]]
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
  [ "$(git config --file "$AGENTS_ROOT/test-agent/.gitconfig" user.name)" = "Persona Author" ]
  [ "$(git config --file "$AGENTS_ROOT/test-agent/.gitconfig" user.email)" = "commits@example.test" ]
  [ "$(git config --file "$AGENTS_ROOT/test-agent/.gitconfig" user.signingkey)" = "ABCDEF1234567890ABCDEF1234567890ABCDEF12" ]
  [ "$(git config --file "$AGENTS_ROOT/test-agent/.gitconfig" commit.gpgsign)" = "true" ]
  [ "$(git config --file "$AGENTS_ROOT/test-agent/.gitconfig" gpg.format)" = openpgp ]
  grep -Fx 'ABCDEF1234567890ABCDEF1234567890ABCDEF12' "$FAKE_GPG_STATE.trust"
  ! grep -Fx 'commits@example.test' "$FAKE_GPG_STATE.trust"
  git config --global --get-all "includeIf.gitdir:$AGENTS_ROOT/test-agent/.path" | grep -Fx "$AGENTS_ROOT/test-agent/.gitconfig"
  [[ "$output" == *"github token"*"valid as test-agent-ricon"* ]]
  [[ "$output" != *"fixture-github-token"* ]]
  [[ "$output" != *"PGP FIXTURE KEY"* ]]

  run fold_task homes:auth test-agent --agents-root "$AGENTS_ROOT" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ready":true'* ]]
  [[ "$output" == *"valid as test-agent-ricon; expires in"* ]]
}

@test "homes:auth rejects handle-derived identity when configured persona differs" {
  configure_ready_auth
  config="$AGENTS_ROOT/test-agent/.gitconfig"
  git config --file "$config" user.name test-agent
  git config --file "$config" user.email test-agent@ricon.family

  run fold_task_stdout_only homes:auth test-agent --agents-root "$AGENTS_ROOT" --json --check

  [ "$status" -eq 1 ]
  assert_json_output
  [[ "$output" == *'"name":"Git config","status":"fail"'* ]]
}

@test "homes:auth refuses readiness when configured Git email is unavailable" {
  configure_ready_auth
  export FAKE_MISSING_GIT_FIELD=test-agent/git/email

  run fold_task_stdout_only homes:auth test-agent --agents-root "$AGENTS_ROOT" --json --check

  [ "$status" -eq 1 ]
  assert_json_output
  [[ "$output" == *'missing or empty configured Git identity'* ]]
}

@test "homes:auth:setup refuses missing Git identity before any local mutation" {
  export FAKE_MISSING_GIT_FIELD=test-agent/git/name

  run fold_task homes:auth:setup test-agent --agents-root "$AGENTS_ROOT" --yes

  [ "$status" -eq 1 ]
  [[ "$output" == *'missing test-agent/git/name'* ]]
  [ ! -f "$FAKE_GPG_STATE" ]
  [ ! -f "$AGENTS_ROOT/test-agent/.gitconfig" ]
  [ ! -s "$GIT_CONFIG_GLOBAL" ]
}

@test "homes:auth:setup refuses empty Git email before any local mutation" {
  export FAKE_GIT_EMAIL=''

  run fold_task homes:auth:setup test-agent --agents-root "$AGENTS_ROOT" --yes

  [ "$status" -eq 1 ]
  [[ "$output" == *'test-agent/git/email is empty'* ]]
  [ ! -f "$FAKE_GPG_STATE" ]
  [ ! -f "$AGENTS_ROOT/test-agent/.gitconfig" ]
  [ ! -s "$GIT_CONFIG_GLOBAL" ]
}

@test "homes:auth:setup preserves configured name punctuation through Git config serialization" {
  export FAKE_GIT_NAME='A "Quoted" \\ Name # team'

  run fold_task homes:auth:setup test-agent --agents-root "$AGENTS_ROOT" --yes

  [ "$status" -eq 0 ]
  [ "$(git config --file "$AGENTS_ROOT/test-agent/.gitconfig" user.name)" = "$FAKE_GIT_NAME" ]

  run fold_task homes:auth test-agent --agents-root "$AGENTS_ROOT" --json --check

  [ "$status" -eq 0 ]
  assert_json_output
  [[ "$output" == *'"ready":true'* ]]
}

@test "homes:auth:setup --home targets the supplied home parent" {
  custom_agent_dir="$BATS_TEST_TMPDIR/custom-workspace/test-agent"
  custom_home="$custom_agent_dir/home"

  run fold_task homes:auth:setup test-agent \
    --agents-root "$AGENTS_ROOT" \
    --home "$custom_home" \
    --yes

  [ "$status" -eq 0 ]
  [ -f "$FAKE_GPG_STATE" ]
  [ -f "$custom_agent_dir/.gitconfig" ]
  [ ! -f "$AGENTS_ROOT/test-agent/.gitconfig" ]
  [ "$(git config --file "$custom_agent_dir/.gitconfig" user.name)" = "Persona Author" ]
  git config --global --get-all "includeIf.gitdir:$custom_agent_dir/.path" | grep -Fx "$custom_agent_dir/.gitconfig"

  run fold_task homes:auth test-agent \
    --agents-root "$AGENTS_ROOT" \
    --home "$custom_home" \
    --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"ready":true'* ]]
  [[ "$output" == *"$custom_agent_dir/.gitconfig"* ]]
  [[ "$output" != *"$AGENTS_ROOT/test-agent/.gitconfig"* ]]
}
