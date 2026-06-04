#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load test_helper

setup() {
  TMPBIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$TMPBIN"
  export TMPBIN
  write_homes_preflight_mocks
}

write_homes_preflight_mocks() {
  cat > "$TMPBIN/secrets" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" != "get" ]; then
  echo "unexpected secrets command: $*" >&2
  exit 2
fi
case "${2:-}" in
  test-agent/gpg-fingerprint) echo "ABCDEF1234567890" ;;
  test-agent/github-username) echo "test-agent-ricon" ;;
  test-agent/github-pat) echo "ghp_not_a_real_token" ;;
  *) echo "missing secret: ${2:-}" >&2; exit 1 ;;
esac
SH
  chmod +x "$TMPBIN/secrets"
  export SECRETS="$TMPBIN/secrets"

  cat > "$TMPBIN/gpg" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "--list-secret-keys" ] && [ "${2:-}" = "ABCDEF1234567890" ]; then
  echo "sec   ed25519/ABCDEF1234567890"
  exit 0
fi
echo "unexpected gpg command: $*" >&2
exit 2
SH
  chmod +x "$TMPBIN/gpg"
  export GPG="$TMPBIN/gpg"
}

create_clean_home() {
  local home="$1"
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
  printf 'fake notes manifest\n' > "$home/notes/.manifest"
  printf 'fake modules manifest\n' > "$home/.modules/manifest"

  git -C "$home" add AGENTS.md mise.toml .mise notes/.manifest .modules/manifest
  git -C "$home" \
    -c user.name="fixture" \
    -c user.email="fixture@example.test" \
    -c commit.gpgsign=false \
    commit -q -m "initial"
}

@test "homes:preflight redacts GitHub tokens embedded in origin URLs" {
  home="$BATS_TEST_TMPDIR/home"
  create_clean_home "$home"
  git -C "$home" remote add origin "https://x-access-token:ghp_secretfixturetoken@github.com/test-agent/home.git"

  run fold_task homes:preflight test-agent --home "$home"

  [ "$status" -eq 0 ]
  [[ "$output" == *"info   origin"*"[REDACTED_GITHUB_TOKEN]"* ]]
  [[ "$output" != *"ghp_secretfixturetoken"* ]]
}

@test "homes:preflight passes a clean already-provisioned home" {
  home="$BATS_TEST_TMPDIR/home"
  create_clean_home "$home"

  run fold_task homes:preflight test-agent --home "$home"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Homes preflight"* ]]
  [[ "$output" == *"ok     home repo"*"git repository present"* ]]
  [[ "$output" == *"ok     worktree"*"clean"* ]]
  [[ "$output" == *"ok     secret:gpg-fingerprint"*"present"* ]]
  [[ "$output" == *"ok     gpg secret key"*"present for stored fingerprint"* ]]
  [[ "$output" == *"overall: pass"* ]]
}

@test "homes:preflight fails closed when the secrets tool is unavailable" {
  home="$BATS_TEST_TMPDIR/home"
  create_clean_home "$home"
  export SECRETS="$TMPBIN/missing-secrets"

  run fold_task homes:preflight test-agent --home "$home"

  [ "$status" -eq 1 ]
  [[ "$output" == *"fail   secret:gpg-fingerprint"*"secrets tool unavailable"* ]]
  [[ "$output" == *"fail   secret:github-username"*"secrets tool unavailable"* ]]
  [[ "$output" == *"fail   secret:github-pat"*"secrets tool unavailable"* ]]
}

@test "homes:preflight fails closed when gpg is unavailable" {
  home="$BATS_TEST_TMPDIR/home"
  create_clean_home "$home"
  export GPG="$TMPBIN/missing-gpg"

  run fold_task homes:preflight test-agent --home "$home"

  [ "$status" -eq 1 ]
  [[ "$output" == *"fail   gpg secret key"*"gpg tool unavailable"* ]]
}

@test "homes:preflight fails closed when notes is unavailable for a notes-managed home" {
  home="$BATS_TEST_TMPDIR/home"
  create_clean_home "$home"
  export NOTES="$TMPBIN/missing-notes"

  run fold_task homes:preflight test-agent --home "$home"

  [ "$status" -eq 1 ]
  [[ "$output" == *"fail   notes changes"*"notes tool unavailable"* ]]
}

@test "homes:preflight fails when the home path is missing" {
  run fold_task homes:preflight test-agent --home "$BATS_TEST_TMPDIR/missing-home"

  [ "$status" -eq 1 ]
  [[ "$output" == *"fail   home repo"*"missing path"* ]]
  [[ "$output" == *"overall: fail"* ]]
}

@test "homes:preflight fails when the home worktree is dirty" {
  home="$BATS_TEST_TMPDIR/home"
  create_clean_home "$home"
  printf '\nlocal edit\n' >> "$home/AGENTS.md"

  run fold_task homes:preflight test-agent --home "$home"

  [ "$status" -eq 1 ]
  [[ "$output" == *"fail   worktree"*"dirty"* ]]
  [[ "$output" == *" M AGENTS.md"* ]]
  [[ "$output" == *"overall: fail"* ]]
}

@test "homes:preflight fails when ignored readable note changes are pending" {
  home="$BATS_TEST_TMPDIR/home"
  create_clean_home "$home"
  printf 'notes/*.md\n' >> "$home/.git/info/exclude"
  printf '# Status\n' > "$home/notes/status.md"

  run fold_task homes:preflight test-agent --home "$home"

  [ "$status" -eq 1 ]
  [[ "$output" == *"ok     worktree"*"clean"* ]]
  [[ "$output" == *"fail   notes changes"*"readable note changes pending"* ]]
  [[ "$output" == *"new:"*"status.md"* ]]
}

@test "homes:preflight fails when readable note filenames are tracked" {
  home="$BATS_TEST_TMPDIR/home"
  create_clean_home "$home"
  printf '# Status\n' > "$home/notes/status.md"
  git -C "$home" add notes/status.md
  git -C "$home" \
    -c user.name="fixture" \
    -c user.email="fixture@example.test" \
    -c commit.gpgsign=false \
    commit -q -m "track readable note"

  run fold_task homes:preflight test-agent --home "$home"

  [ "$status" -eq 1 ]
  [[ "$output" == *"fail   tracked readable notes"* ]]
  [[ "$output" == *"notes/status.md"* ]]
}

@test "homes:preflight rejects invalid agent names" {
  home="$BATS_TEST_TMPDIR/home"
  create_clean_home "$home"

  run fold_task homes:preflight "bad/agent" --home "$home"

  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid agent name"* ]]
}
