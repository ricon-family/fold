#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load test_helper

create_simple_home() {
  local home="$1"
  mkdir -p "$home"
  git init -q -b main "$home"
  cat > "$home/AGENTS.md" <<'MD'
# test-agent home
MD
  git -C "$home" add AGENTS.md
  git -C "$home" \
    -c user.name="fixture" \
    -c user.email="fixture@example.test" \
    -c commit.gpgsign=false \
    commit -q -m "initial"
}

create_publishable_home() {
  local home="$1"
  mkdir -p "$home/notes" "$home/.modules"
  git init -q -b main "$home"

  cat > "$home/AGENTS.md" <<'MD'
# test-agent home
MD
  printf '\0GITCRYPT\0notes manifest\n' > "$home/notes/.manifest"
  printf '\0GITCRYPT\0private status note\n' > "$home/notes/abcdef12"
  printf '\0GITCRYPT\0modules manifest\n' > "$home/.modules/manifest"

  git -C "$home" add AGENTS.md notes/.manifest notes/abcdef12 .modules/manifest
  git -C "$home" \
    -c user.name="fixture" \
    -c user.email="fixture@example.test" \
    -c commit.gpgsign=false \
    commit -q -m "bootstrap fixture home"
}

create_plaintext_home() {
  local home="$1"
  mkdir -p "$home/notes" "$home/.modules"
  git init -q -b main "$home"

  cat > "$home/AGENTS.md" <<'MD'
# test-agent home
MD
  printf 'plaintext notes manifest\n' > "$home/notes/.manifest"
  printf 'plaintext private status note\n' > "$home/notes/abcdef12"
  printf 'plaintext modules manifest\n' > "$home/.modules/manifest"

  git -C "$home" add AGENTS.md notes/.manifest notes/abcdef12 .modules/manifest
  git -C "$home" \
    -c user.name="fixture" \
    -c user.email="fixture@example.test" \
    -c commit.gpgsign=false \
    commit -q -m "bootstrap plaintext home"
}

create_mixed_note_home() {
  local home="$1"
  mkdir -p "$home/notes" "$home/.modules"
  git init -q -b main "$home"

  cat > "$home/AGENTS.md" <<'MD'
# test-agent home
MD
  printf '\0GITCRYPT\0notes manifest\n' > "$home/notes/.manifest"
  printf '\0GITCRYPT\0first private note\n' > "$home/notes/aaaa1111"
  printf 'PLAINTEXT SECOND NOTE SHOULD NOT PUBLISH\n' > "$home/notes/zzzz9999"
  printf '\0GITCRYPT\0modules manifest\n' > "$home/.modules/manifest"

  git -C "$home" add AGENTS.md notes/.manifest notes/aaaa1111 notes/zzzz9999 .modules/manifest
  git -C "$home" \
    -c user.name="fixture" \
    -c user.email="fixture@example.test" \
    -c commit.gpgsign=false \
    commit -q -m "bootstrap mixed-note home"
}

create_bare_remote() {
  local remote="$1"
  git init -q --bare -b main "$remote"
}

assert_remote_blob_matches_source() {
  local home="$1" remote="$2" path="$3"
  local source_blob="$BATS_TEST_TMPDIR/source-${path//\//-}"
  local remote_blob="$BATS_TEST_TMPDIR/remote-${path//\//-}"

  git -C "$home" cat-file -p "HEAD:$path" > "$source_blob"
  git --git-dir="$remote" cat-file -p "refs/heads/main:$path" > "$remote_blob"
  cmp "$source_blob" "$remote_blob"
}

write_archive_guard_git() {
  local path="$BATS_TEST_TMPDIR/git"
  local real_git
  real_git=$(command -v git)

  cat > "$path" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
for arg in "$@"; do
  if [ "$arg" = "archive" ]; then
    echo "git archive must not be used for homes:publish-fresh" >&2
    exit 99
  fi
done
exec "$REAL_GIT" "$@"
SH
  chmod +x "$path"
  export REAL_GIT="$real_git"
  export GIT="$path"
}

write_mock_git_leaking_ls_remote_failure() {
  local path="$BATS_TEST_TMPDIR/git-leak-ls-remote"
  local real_git
  real_git=$(command -v git)

  cat > "$path" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
for arg in "$@"; do
  if [ "$arg" = "ls-remote" ]; then
    echo "fatal: could not read from https://x-access-token:ghp_secretfixturetoken@github.com/test-agent/home.git" >&2
    exit 128
  fi
done
exec "$REAL_GIT" "$@"
SH
  chmod +x "$path"
  export REAL_GIT="$real_git"
  export GIT="$path"
}

write_mock_git_ls_remote_success() {
  local path="$BATS_TEST_TMPDIR/git-ls-remote-success"
  local real_git
  real_git=$(command -v git)

  cat > "$path" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
for arg in "$@"; do
  if [ "$arg" = "ls-remote" ]; then
    printf '0000000000000000000000000000000000000000\trefs/heads/main\n'
    exit 0
  fi
done
exec "$REAL_GIT" "$@"
SH
  chmod +x "$path"
  export REAL_GIT="$real_git"
  export GIT="$path"
}

write_mock_git_clone_partial_failure() {
  local path="$BATS_TEST_TMPDIR/git-clone-partial-fail"
  local real_git
  real_git=$(command -v git)

  cat > "$path" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
for arg in "$@"; do
  if [ "$arg" = "ls-remote" ]; then
    printf '0000000000000000000000000000000000000000\trefs/heads/main\n'
    exit 0
  fi
  if [ "$arg" = "clone" ]; then
    target=""
    for value in "$@"; do target="$value"; done
    mkdir -p "$target"
    printf 'partial clone\n' > "$target/PARTIAL_CLONE"
    echo "fatal: clone failed after creating target" >&2
    exit 42
  fi
done
exec "$REAL_GIT" "$@"
SH
  chmod +x "$path"
  export REAL_GIT="$real_git"
  export GIT="$path"
}

write_mock_secrets_test_agent_github() {
  local path="$BATS_TEST_TMPDIR/secrets-github"
  cat > "$path" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" != "get" ]; then
  echo "unexpected secrets command: $*" >&2
  exit 2
fi
case "${2:-}" in
  test-agent/github-pat) echo "fixture-github-token" ;;
  *) echo "missing secret: ${2:-}" >&2; exit 1 ;;
esac
SH
  chmod +x "$path"
  export SECRETS="$path"
}

write_mock_git_requires_gh_token_for_adopt() {
  local path="$BATS_TEST_TMPDIR/git-requires-gh-token"
  local real_git
  real_git=$(command -v git)

  cat > "$path" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
record_token() {
  local phase="$1" token_status=empty
  shift
  [ -n "${GH_TOKEN:-}" ] && token_status=set
  printf '%s token=%s args=%s\n' "$phase" "$token_status" "$*" >> "${FAKE_GIT_AUTH_LOG:?}"
  [ "${GH_TOKEN:-}" = "fixture-github-token" ] || exit 70
}

if [ "${1:-}" = "ls-remote" ]; then
  record_token ls-remote "$@"
  printf '0000000000000000000000000000000000000000\trefs/heads/main\n'
  exit 0
fi

if [ "${1:-}" = "clone" ]; then
  record_token clone "$@"
  target=""
  for value in "$@"; do target="$value"; done
  exec "$REAL_GIT" clone -q --branch main "${FAKE_REMOTE_SOURCE:?}" "$target"
fi

exec "$REAL_GIT" "$@"
SH
  chmod +x "$path"
  export REAL_GIT="$real_git"
  export GIT="$path"
}

write_mock_notes_no_changes() {
  local path="$BATS_TEST_TMPDIR/notes-clean"
  cat > "$path" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "changes" ] && [ "${2:-}" = "--summary" ]; then
  echo "No changes."
  exit 0
fi
echo "unexpected notes command: $*" >&2
exit 2
SH
  chmod +x "$path"
  export NOTES="$path"
}

write_mock_notes_with_pending_changes() {
  local path="$BATS_TEST_TMPDIR/notes"
  cat > "$path" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  stage|obfuscate)
    exit 0
    ;;
  changes)
    if [ "${2:-}" = "--summary" ]; then
      printf '  modified:  status.md\n\n1 change(s): 1 modified, 0 new, 0 deleted, 0 stale-readable\n'
      exit 0
    fi
    ;;
esac
echo "unexpected notes command: $*" >&2
exit 2
SH
  chmod +x "$path"
  export NOTES="$path"
}

write_mock_mise_trust_logger() {
  local path="$BATS_TEST_TMPDIR/mise-trust-logger"
  export MISE_TRUST_LOG="$BATS_TEST_TMPDIR/mise-trust.log"
  : > "$MISE_TRUST_LOG"
  cat > "$path" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s %s\n' "${1:-}" "$(pwd -P)" >> "${MISE_TRUST_LOG:?}"
case "${1:-}" in
  trust|install|welcome)
    exit 0
    ;;
  run)
    if [ "${2:-}" = "agent:prepare" ]; then
      exit 0
    fi
    ;;
esac
echo "unexpected mise command: $*" >&2
exit 2
SH
  chmod +x "$path"
  export MISE="$path"
}

create_mise_home_with_module_configs() {
  local home="$1"
  create_simple_home "$home"
  cat > "$home/mise.toml" <<'TOML'
[tools]
node = "20"
TOML
  printf 'modules/\n' > "$home/.gitignore"
  git -C "$home" add mise.toml .gitignore
  git -C "$home" \
    -c user.name="fixture" \
    -c user.email="fixture@example.test" \
    -c commit.gpgsign=false \
    commit -q -m "add mise config"

  mkdir -p "$home/modules/fold" "$home/modules/den"
  cat > "$home/modules/fold/mise.toml" <<'TOML'
[tools]
node = "20"
TOML
  cat > "$home/modules/den/mise.toml" <<'TOML'
[tools]
node = "20"
TOML
}

@test "homes:publish-fresh dry-run verifies encrypted blobs without pushing" {
  home="$BATS_TEST_TMPDIR/home"
  remote="$BATS_TEST_TMPDIR/home.git"
  create_publishable_home "$home"
  create_bare_remote "$remote"
  write_mock_notes_no_changes

  run fold_task homes:publish-fresh test-agent \
    --home "$home" \
    --remote-url "$remote" \
    --no-gpg-sign

  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run: would create a fresh root commit from HEAD^{tree}"* ]]
  [[ "$output" == *"encrypted: HEAD:notes/.manifest"* ]]
  run git --git-dir="$remote" show-ref --verify refs/heads/main
  [ "$status" -ne 0 ]
}

@test "homes:publish-fresh dry-run fails when the remote is unreachable" {
  home="$BATS_TEST_TMPDIR/home"
  create_publishable_home "$home"
  write_mock_notes_no_changes

  run fold_task homes:publish-fresh test-agent \
    --home "$home" \
    --remote-url "$BATS_TEST_TMPDIR/missing.git" \
    --no-gpg-sign

  [ "$status" -eq 1 ]
  [[ "$output" == *"remote is not reachable"* ]]
}

@test "homes:publish-fresh redacts tokens in remote output and errors" {
  home="$BATS_TEST_TMPDIR/home"
  create_publishable_home "$home"
  write_mock_notes_no_changes
  write_mock_git_leaking_ls_remote_failure

  run fold_task homes:publish-fresh test-agent \
    --home "$home" \
    --remote-url "https://x-access-token:ghp_secretfixturetoken@github.com/test-agent/home.git" \
    --no-gpg-sign

  [ "$status" -eq 1 ]
  [[ "$output" == *"[REDACTED_GITHUB_TOKEN]"* ]]
  [[ "$output" != *"ghp_secretfixturetoken"* ]]
}

@test "homes:publish-fresh creates a root commit preserving encrypted tree blobs" {
  home="$BATS_TEST_TMPDIR/home"
  remote="$BATS_TEST_TMPDIR/home.git"
  create_publishable_home "$home"
  create_bare_remote "$remote"
  write_mock_notes_no_changes
  write_archive_guard_git

  run fold_task homes:publish-fresh test-agent \
    --home "$home" \
    --remote-url "$remote" \
    --no-gpg-sign \
    --yes

  [ "$status" -eq 0 ]
  [[ "$output" == *"fresh root commit:"* ]]
  parents=$(git --git-dir="$remote" rev-list --parents -n1 refs/heads/main)
  set -- $parents
  [ "$#" -eq 1 ]
  assert_remote_blob_matches_source "$home" "$remote" notes/.manifest
  assert_remote_blob_matches_source "$home" "$remote" notes/abcdef12
  assert_remote_blob_matches_source "$home" "$remote" .modules/manifest
}

@test "homes:publish-fresh rejects plaintext publication blobs" {
  home="$BATS_TEST_TMPDIR/home"
  remote="$BATS_TEST_TMPDIR/home.git"
  create_plaintext_home "$home"
  create_bare_remote "$remote"
  write_mock_notes_no_changes

  run fold_task homes:publish-fresh test-agent \
    --home "$home" \
    --remote-url "$remote" \
    --no-gpg-sign \
    --yes

  [ "$status" -eq 1 ]
  [[ "$output" == *"not a git-crypt blob"* ]]
  run git --git-dir="$remote" show-ref --verify refs/heads/main
  [ "$status" -ne 0 ]
}

@test "homes:publish-fresh rejects a plaintext second obfuscated note" {
  home="$BATS_TEST_TMPDIR/home"
  remote="$BATS_TEST_TMPDIR/home.git"
  create_mixed_note_home "$home"
  create_bare_remote "$remote"
  write_mock_notes_no_changes

  run fold_task homes:publish-fresh test-agent \
    --home "$home" \
    --remote-url "$remote" \
    --no-gpg-sign \
    --yes

  [ "$status" -eq 1 ]
  [[ "$output" == *"HEAD:notes/zzzz9999 is not a git-crypt blob"* ]]
  run git --git-dir="$remote" show-ref --verify refs/heads/main
  [ "$status" -ne 0 ]
}

@test "homes:publish-fresh rejects ignored readable note changes before publishing" {
  home="$BATS_TEST_TMPDIR/home"
  remote="$BATS_TEST_TMPDIR/home.git"
  create_publishable_home "$home"
  create_bare_remote "$remote"
  printf 'notes/*.md\n' >> "$home/.git/info/exclude"
  printf '# pending readable status\n' > "$home/notes/status.md"
  write_mock_notes_with_pending_changes

  run fold_task homes:publish-fresh test-agent \
    --home "$home" \
    --remote-url "$remote" \
    --no-gpg-sign \
    --yes

  [ "$status" -eq 1 ]
  [[ "$output" == *"note changes remain"* ]]
  [[ "$output" == *"modified:"*"status.md"* ]]
  run git --git-dir="$remote" show-ref --verify refs/heads/main
  [ "$status" -ne 0 ]
}

@test "homes:commit-local dry-run does not create a commit" {
  home="$BATS_TEST_TMPDIR/home"
  create_simple_home "$home"
  before=$(git -C "$home" rev-parse HEAD)
  printf '\nlocal edit\n' >> "$home/AGENTS.md"

  run fold_task homes:commit-local test-agent --home "$home" --no-gpg-sign

  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run: would stage bootstrap surfaces"* ]]
  after=$(git -C "$home" rev-parse HEAD)
  [ "$before" = "$after" ]
  git -C "$home" diff --quiet --cached
}

@test "homes:commit-local --yes commits bootstrap surfaces with agent identity" {
  home="$BATS_TEST_TMPDIR/home"
  create_simple_home "$home"
  printf '\nlocal edit\n' >> "$home/AGENTS.md"

  run fold_task homes:commit-local test-agent \
    --home "$home" \
    --message "bootstrap test-agent home" \
    --no-gpg-sign \
    --yes

  [ "$status" -eq 0 ]
  git -C "$home" diff --quiet
  author=$(git -C "$home" log -1 --format='%an <%ae>')
  [ "$author" = "test-agent <test-agent@ricon.family>" ]
  subject=$(git -C "$home" log -1 --format='%s')
  [ "$subject" = "bootstrap test-agent home" ]
}

@test "homes:commit-local --yes fails when notes remain dirty after staging" {
  home="$BATS_TEST_TMPDIR/home"
  create_simple_home "$home"
  mkdir -p "$home/notes"
  printf 'fake manifest\n' > "$home/notes/.manifest"
  git -C "$home" add notes/.manifest
  git -C "$home" \
    -c user.name="fixture" \
    -c user.email="fixture@example.test" \
    -c commit.gpgsign=false \
    commit -q -m "add notes manifest"
  before=$(git -C "$home" rev-parse HEAD)
  write_mock_notes_with_pending_changes

  run fold_task homes:commit-local test-agent \
    --home "$home" \
    --no-gpg-sign \
    --yes

  [ "$status" -eq 1 ]
  [[ "$output" == *"note changes remain after staging"* ]]
  after=$(git -C "$home" rev-parse HEAD)
  [ "$before" = "$after" ]
}

@test "homes:adopt-remote redacts tokens in remote output" {
  home="$BATS_TEST_TMPDIR/workspace/home"
  create_simple_home "$home"
  write_mock_git_ls_remote_success

  run fold_task homes:adopt-remote test-agent \
    --home "$home" \
    --remote-url "https://x-access-token:ghp_secretfixturetoken@github.com/test-agent/home.git" \
    --no-prepare

  [ "$status" -eq 0 ]
  [[ "$output" == *"[REDACTED_GITHUB_TOKEN]"* ]]
  [[ "$output" != *"ghp_secretfixturetoken"* ]]
}

@test "homes:adopt-remote --repo sets agent GitHub token for private remote checks and clone" {
  source_home="$BATS_TEST_TMPDIR/source-home"
  remote="$BATS_TEST_TMPDIR/home.git"
  home="$BATS_TEST_TMPDIR/workspace/home"
  create_publishable_home "$source_home"
  git clone -q --bare "$source_home" "$remote"
  export FAKE_REMOTE_SOURCE="$remote"
  export FAKE_GIT_AUTH_LOG="$BATS_TEST_TMPDIR/git-auth.log"
  : > "$FAKE_GIT_AUTH_LOG"
  write_mock_secrets_test_agent_github
  write_mock_git_requires_gh_token_for_adopt

  run fold_task homes:adopt-remote test-agent \
    --home "$home" \
    --repo test-agent/home \
    --no-prepare \
    --yes

  [ "$status" -eq 0 ]
  [ -f "$home/notes/abcdef12" ]
  grep -F "ls-remote token=set args=ls-remote --exit-code https://github.com/test-agent/home.git refs/heads/main" "$FAKE_GIT_AUTH_LOG" >/dev/null
  grep -F "clone token=set args=clone --branch main https://github.com/test-agent/home.git $home" "$FAKE_GIT_AUTH_LOG" >/dev/null
  [[ "$output" != *"fixture-github-token"* ]]
}

@test "homes:adopt-remote --yes backs up clean local history and clones remote" {
  source_home="$BATS_TEST_TMPDIR/source-home"
  remote="$BATS_TEST_TMPDIR/home.git"
  home="$BATS_TEST_TMPDIR/workspace/home"
  create_publishable_home "$source_home"
  git clone -q --bare "$source_home" "$remote"
  create_simple_home "$home"

  run fold_task homes:adopt-remote test-agent \
    --home "$home" \
    --remote-url "$remote" \
    --no-prepare \
    --yes

  [ "$status" -eq 0 ]
  [[ "$output" == *"moved old local history to:"* ]]
  [[ "$output" == *"backup retained:"* ]]
  [ -f "$home/notes/abcdef12" ]
  backups=("$home".local-history-*)
  [ -d "${backups[0]}" ]
}

@test "homes:adopt-remote restores the old home if clone leaves a partial target" {
  home="$BATS_TEST_TMPDIR/workspace/home"
  create_simple_home "$home"
  write_mock_git_clone_partial_failure

  run fold_task homes:adopt-remote test-agent \
    --home "$home" \
    --remote-url "$BATS_TEST_TMPDIR/home.git" \
    --no-prepare \
    --yes

  [ "$status" -eq 42 ]
  [[ "$output" == *"restored old home after failure"* ]]
  [ -f "$home/AGENTS.md" ]
  [[ "$(cat "$home/AGENTS.md")" == *"test-agent home"* ]]
  [ ! -f "$home/PARTIAL_CLONE" ]
}

@test "homes:smoke --skip-mise passes a clean simple home" {
  home="$BATS_TEST_TMPDIR/home"
  create_simple_home "$home"

  run fold_task homes:smoke test-agent --home "$home" --skip-mise

  [ "$status" -eq 0 ]
  [[ "$output" == *"Homes smoke"* ]]
  [[ "$output" == *"== repo =="* ]]
  [[ "$output" == *"== mise =="*"skipped"* ]]
}

@test "homes:smoke trusts mise configs in the home and present modules" {
  home="$BATS_TEST_TMPDIR/home"
  create_mise_home_with_module_configs "$home"
  write_mock_mise_trust_logger

  run fold_task homes:smoke test-agent --home "$home"

  [ "$status" -eq 0 ]
  grep -F "trust $(cd "$home" && pwd -P)" "$MISE_TRUST_LOG" >/dev/null
  grep -F "trust $(cd "$home/modules/fold" && pwd -P)" "$MISE_TRUST_LOG" >/dev/null
  grep -F "trust $(cd "$home/modules/den" && pwd -P)" "$MISE_TRUST_LOG" >/dev/null
}

@test "homes:trust-mise trusts the home and present modules" {
  home="$BATS_TEST_TMPDIR/home"
  create_mise_home_with_module_configs "$home"
  write_mock_mise_trust_logger

  run fold_task homes:trust-mise test-agent --home "$home"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Homes trust-mise"* ]]
  grep -F "trust $(cd "$home" && pwd -P)" "$MISE_TRUST_LOG" >/dev/null
  grep -F "trust $(cd "$home/modules/fold" && pwd -P)" "$MISE_TRUST_LOG" >/dev/null
  grep -F "trust $(cd "$home/modules/den" && pwd -P)" "$MISE_TRUST_LOG" >/dev/null
}

@test "homes:smoke fails closed when notes is unavailable for a notes-managed home" {
  home="$BATS_TEST_TMPDIR/home"
  create_simple_home "$home"
  mkdir -p "$home/notes"
  printf 'fake manifest\n' > "$home/notes/.manifest"
  git -C "$home" add notes/.manifest
  git -C "$home" \
    -c user.name="fixture" \
    -c user.email="fixture@example.test" \
    -c commit.gpgsign=false \
    commit -q -m "add notes manifest"
  export NOTES="$BATS_TEST_TMPDIR/missing-notes"

  run fold_task homes:smoke test-agent --home "$home" --skip-mise

  [ "$status" -eq 1 ]
  [[ "$output" == *"notes tool is unavailable"* ]]
}

@test "homes:smoke fails closed when modules is unavailable for a modules-managed home" {
  home="$BATS_TEST_TMPDIR/home"
  create_simple_home "$home"
  mkdir -p "$home/.modules"
  printf 'fake manifest\n' > "$home/.modules/manifest"
  git -C "$home" add .modules/manifest
  git -C "$home" \
    -c user.name="fixture" \
    -c user.email="fixture@example.test" \
    -c commit.gpgsign=false \
    commit -q -m "add modules manifest"
  export MODULES="$BATS_TEST_TMPDIR/missing-modules"

  run fold_task homes:smoke test-agent --home "$home" --skip-mise

  [ "$status" -eq 1 ]
  [[ "$output" == *"modules tool is unavailable"* ]]
}
