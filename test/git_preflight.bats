#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load test_helper

make_release_repo() {
  local work="$BATS_TEST_TMPDIR/work"
  local remote="$BATS_TEST_TMPDIR/remote.git"

  git init --bare "$remote" >/dev/null
  git init "$work" >/dev/null
  git -C "$work" checkout -b main >/dev/null
  git -C "$work" config user.name "Test Agent"
  git -C "$work" config user.email "test-agent@ricon.family"
  git -C "$work" config commit.gpgsign false

  printf 'hello\n' > "$work/README.md"
  git -C "$work" add README.md
  git -C "$work" commit -m "init" >/dev/null
  git -C "$work" remote add origin "$remote"
  git -C "$work" push -u origin main >/dev/null
  git -C "$remote" symbolic-ref HEAD refs/heads/main

  printf '%s\n' "$work"
}

@test "pre-publish accepts semver prerelease tag suffixes" {
  repo="$(make_release_repo)"

  run fold_task git:pre-publish --tag v1.2.0-kkl.2 "$repo"

  [ "$status" -eq 0 ]
  [[ "$output" == *"tag shape looks like semver: v1.2.0-kkl.2"* ]]
  [[ "$output" == *"local tag does not exist: v1.2.0-kkl.2"* ]]
  [[ "$output" == *"remote tag not found on origin: v1.2.0-kkl.2"* ]]
}

@test "pre-publish rejects malformed semver prerelease tag suffixes" {
  repo="$(make_release_repo)"

  run fold_task git:pre-publish --tag v1.2.0- "$repo"

  [ "$status" -ne 0 ]
  [[ "$output" == *"tag 'v1.2.0-' is not a vMAJOR.MINOR.PATCH[-PRERELEASE][+BUILD] semver tag"* ]]
}
