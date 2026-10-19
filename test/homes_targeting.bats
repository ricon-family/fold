#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load test_helper

@test "single-home commands require --home or AGENT_HOME before using any capability" {
  export AGENT_HOME=
  export GIT=/usr/bin/false GPG=/usr/bin/false SECRETS=/usr/bin/false GH=/usr/bin/false

  for task in homes:auth homes:status homes:preflight homes:auth:setup homes:email:setup \
    homes:commit-local homes:adopt-remote homes:publish-fresh homes:trust-mise homes:smoke; do
    run fold_task "$task" test-agent

    [ "$status" -ne 0 ]
    [[ "$output" == *"provide --home or set AGENT_HOME"* ]]
  done
}

@test "legacy --agents-root alone does not select a home" {
  export AGENT_HOME=

  for task in homes:auth homes:status homes:auth:setup; do
    run fold_task "$task" test-agent --agents-root "$BATS_TEST_TMPDIR/old-layout"

    [ "$status" -ne 0 ]
    [[ "$output" == *"provide --home or set AGENT_HOME"* ]]
    [ ! -e "$BATS_TEST_TMPDIR/old-layout" ]
  done
}

@test "adoption previews AGENT_HOME without accessing secrets or the remote" {
  export AGENT_HOME="$BATS_TEST_TMPDIR/new-desk/home"
  export GIT=/usr/bin/false SECRETS=/usr/bin/false

  run fold_task homes:adopt-remote other-agent --repo other-agent/home

  [ "$status" -eq 0 ]
  [[ "$output" == *"home:   $AGENT_HOME"* ]]
  [[ "$output" == *"dry-run: would move"* ]]
  [[ "$output" == *"agent:prepare"* ]]
  [ ! -e "$AGENT_HOME" ]
}

@test "explicit --home overrides AGENT_HOME regardless of the agent handle" {
  export AGENT_HOME="$BATS_TEST_TMPDIR/active/home"
  target="$BATS_TEST_TMPDIR/chosen/home"
  export GIT=/usr/bin/false SECRETS=/usr/bin/false

  run fold_task homes:adopt-remote other-agent --home "$target" --repo other-agent/home

  [ "$status" -eq 0 ]
  [[ "$output" == *"home:   $target"* ]]
  [[ "$output" != *"$AGENT_HOME"* ]]
  [ ! -e "$target" ]
  [ ! -e "$AGENT_HOME" ]
}
