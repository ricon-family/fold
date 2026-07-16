#!/usr/bin/env bats

load test_helper

setup() {
  MODULE_DIR="$REPO_DIR/modules/welcome-observational-$BATS_TEST_NUMBER-$$"
  REMOTE_DIR="$BATS_TEST_TMPDIR/welcome-module.git"
  WRITER_DIR="$BATS_TEST_TMPDIR/welcome-writer"

  mkdir -p "$REPO_DIR/modules"
  git init -q --bare "$REMOTE_DIR"
  git -C "$REMOTE_DIR" symbolic-ref HEAD refs/heads/main

  git init -q -b main "$MODULE_DIR"
  git -C "$MODULE_DIR" config user.name fixture
  git -C "$MODULE_DIR" config user.email fixture@example.test
  git -C "$MODULE_DIR" config commit.gpgsign false
  mkdir -p "$MODULE_DIR/notes"
  printf 'module fixture\n' > "$MODULE_DIR/README.md"
  : > "$MODULE_DIR/notes/.manifest"
  git -C "$MODULE_DIR" add README.md notes/.manifest
  git -C "$MODULE_DIR" commit -q -m initial
  git -C "$MODULE_DIR" remote add origin "$REMOTE_DIR"
  git -C "$MODULE_DIR" push -q -u origin main

  git clone -q "$REMOTE_DIR" "$WRITER_DIR"
  git -C "$WRITER_DIR" config user.name fixture
  git -C "$WRITER_DIR" config user.email fixture@example.test
  git -C "$WRITER_DIR" config commit.gpgsign false
  printf 'remote update\n' >> "$WRITER_DIR/README.md"
  git -C "$WRITER_DIR" add README.md
  git -C "$WRITER_DIR" commit -q -m update
  git -C "$WRITER_DIR" push -q origin main
}

teardown() {
  rm -rf "$MODULE_DIR"
}

@test "welcome reports nested module drift without fetching or installing hooks" {
  recorded_origin=$(git -C "$MODULE_DIR" rev-parse refs/remotes/origin/main)
  remote_main=$(git --git-dir="$REMOTE_DIR" rev-parse refs/heads/main)
  [ "$recorded_origin" != "$remote_main" ]
  [ ! -e "$MODULE_DIR/.git/hooks/pre-commit" ]

  run fold_task welcome
  [ "$status" -eq 0 ]

  [ "$(git -C "$MODULE_DIR" rev-parse refs/remotes/origin/main)" = "$recorded_origin" ]
  [ ! -e "$MODULE_DIR/.git/hooks/pre-commit" ]
  [[ "$output" == *"at recorded origin/main"* ]]
  [[ "$output" == *"missing → notes install-hooks"* ]]
}
