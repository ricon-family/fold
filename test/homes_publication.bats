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

@test "homes:smoke --skip-mise passes a clean simple home" {
  home="$BATS_TEST_TMPDIR/home"
  create_simple_home "$home"

  run fold_task homes:smoke test-agent --home "$home" --skip-mise

  [ "$status" -eq 0 ]
  [[ "$output" == *"Homes smoke"* ]]
  [[ "$output" == *"== repo =="* ]]
  [[ "$output" == *"== mise =="*"skipped"* ]]
}
