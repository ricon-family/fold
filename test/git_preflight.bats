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

make_preflight_repo() {
  local work="$BATS_TEST_TMPDIR/preflight-work"

  git init "$work" >/dev/null
  git -C "$work" checkout -b main >/dev/null
  git -C "$work" config user.name "Test Agent"
  git -C "$work" config user.email "test-agent@ricon.family"
  git -C "$work" config commit.gpgsign false

  printf 'hello\n' > "$work/README.md"
  git -C "$work" add README.md

  (cd "$work" && pwd -P)
}

install_preflight_shims() {
  local bin="$BATS_TEST_TMPDIR/bin"

  fold_task git:install-shims --bin-dir "$bin" >/dev/null

  printf '%s\n' "$bin"
}

make_agent_home_with_fold_module() {
  local agent_home="$BATS_TEST_TMPDIR/agent-home"

  mkdir -p "$agent_home/modules"
  ln -s "$REPO_DIR" "$agent_home/modules/fold"

  printf '%s\n' "$agent_home"
}

@test "installed git shims require AGENT_HOME instead of legacy home discovery" {
  bin="$(install_preflight_shims)"
  legacy_home="$BATS_TEST_TMPDIR/legacy-home"
  mkdir -p "$legacy_home/agents/x1f9/home/modules"
  ln -s "$REPO_DIR" "$legacy_home/agents/x1f9/home/modules/fold"

  run env \
    AGENT_HOME= \
    HOME="$legacy_home" \
    GIT_AUTHOR_NAME=x1f9 \
    GIT_AUTHOR_EMAIL=x1f9@ricon.family \
    "$bin/git-pre-push"

  [ "$status" -ne 0 ]
  [[ "$output" == *"AGENT_HOME is not set"* ]]
}

@test "installed git shims resolve fold from AGENT_HOME modules" {
  bin="$(install_preflight_shims)"
  agent_home="$(make_agent_home_with_fold_module)"
  repo="$(make_preflight_repo)"

  run env \
    AGENT_HOME="$agent_home" \
    GIT_AUTHOR_NAME=desk-agent \
    GIT_AUTHOR_EMAIL=desk-agent@ricon.family \
    GIT_COMMITTER_NAME=desk-agent \
    GIT_COMMITTER_EMAIL=desk-agent@ricon.family \
    PATH="$bin:$PATH" \
    bash -c 'cd "$1" && git pre-commit' bash "$repo"

  [ "$status" -eq 0 ]
  [[ "$output" == *"fold git:pre-commit"* ]]
  [[ "$output" == *"default target: caller cwd ($repo)"* ]]
  [[ "$output" == *"repo: $repo"* ]]
  [[ "$output" == *"active agent: desk-agent"* ]]
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
