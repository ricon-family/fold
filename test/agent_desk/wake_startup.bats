#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load ../test_helper
load helpers
load shell
load startup_helpers

# Shell records submission; Sessions supplies synthetic process observations.
setup() {
  setup_desk_test
  setup_shell_mock
  setup_sessions_mock
}

@test "agent:desk:wake --session detects a new process for the same session ID" {
  home="$BATS_TEST_TMPDIR/home"
  work_dir="$BATS_TEST_TMPDIR/continue"
  packet="$BATS_TEST_TMPDIR/follow-up.md"
  make_repo "$home" home
  printf 'continue packet\n' > "$packet"
  home_real=$(cd "$home" && pwd -P)
  export FAKE_SESSION_CWD="$home_real"
  export FAKE_TARGET_SESSION_ID=session-123

  run fold_task agent:desk:wake quick \
    --session session-123 \
    --home "$home" \
    --shell quick-cont \
    --packet "$packet" \
    --model openai-codex/gpt-5.6-sol \
    --work-dir "$work_dir" \
    --yes

  [ "$status" -eq 0 ]
  [[ "$output" == *"Agent wake ready"* ]]
  [[ "$output" == *"mode:    resume"* ]]
  [[ "$output" == *"session: session-123"* ]]
  [[ "$output" == *"attach:  shell attach quick-cont"* ]]
  work_real=$(cd "$work_dir" && pwd -P)
  grep -q "shell run --probe-ready --ready-timeout 10 --cwd $home_real quick-cont $work_real/start-quick-cont.sh" "$SHELL_LOG"
  [ "$(cat "$SESSIONS_CALLS")" -ge 2 ]
}

@test "agent:desk:wake --session rejects another agent's session before launch" {
  home="$BATS_TEST_TMPDIR/home"
  work_dir="$BATS_TEST_TMPDIR/continue"
  packet="$BATS_TEST_TMPDIR/follow-up.md"
  make_repo "$home" home
  printf 'continue packet\n' > "$packet"
  home_real=$(cd "$home" && pwd -P)
  export FAKE_SESSION_CWD="$home_real"
  export FAKE_SESSION_AGENT=junior
  export FAKE_TARGET_SESSION_ID=session-123

  run fold_task agent:desk:wake quick \
    --session session-123 \
    --home "$home" \
    --shell quick-cont \
    --packet "$packet" \
    --model openai-codex/gpt-5.6-sol \
    --work-dir "$work_dir" \
    --yes

  [ "$status" -ne 0 ]
  [[ "$output" == *"session session-123 belongs to junior, expected quick"* ]]
  [ ! -e "$SHELL_RUN_MARKER" ]
  ! grep -q '^sessions wake ' "$SESSIONS_LOG"
}

@test "agent:desk:wake --session rejects another desk before launch" {
  home="$BATS_TEST_TMPDIR/home"
  other_home="$BATS_TEST_TMPDIR/other-home"
  work_dir="$BATS_TEST_TMPDIR/continue"
  packet="$BATS_TEST_TMPDIR/follow-up.md"
  make_repo "$home" home
  mkdir -p "$other_home"
  printf 'continue packet\n' > "$packet"
  home_real=$(cd "$home" && pwd -P)
  other_home_real=$(cd "$other_home" && pwd -P)
  export FAKE_SESSION_CWD="$home_real"
  export FAKE_SESSION_META_CWD="$other_home_real"
  export FAKE_TARGET_SESSION_ID=session-123

  run fold_task agent:desk:wake quick \
    --session session-123 \
    --home "$home" \
    --shell quick-cont \
    --packet "$packet" \
    --model openai-codex/gpt-5.6-sol \
    --work-dir "$work_dir" \
    --yes

  [ "$status" -ne 0 ]
  [[ "$output" == *"session cwd does not match prepared target home"* ]]
  [[ "$output" == *"session cwd: $other_home_real"* ]]
  [[ "$output" == *"target home: $home_real"* ]]
  [ ! -e "$SHELL_RUN_MARKER" ]
  ! grep -q '^sessions wake ' "$SESSIONS_LOG"
}

@test "agent:desk:wake --yes waits for a new live Pi process" {
  home="$BATS_TEST_TMPDIR/home"
  work_dir="$BATS_TEST_TMPDIR/wake"
  packet="$BATS_TEST_TMPDIR/packet.md"
  make_repo "$home" home
  printf 'hello packet\n' > "$packet"

  home_real=$(cd "$home" && pwd -P)
  export FAKE_SESSION_CWD="$home_real"

  run fold_task agent:desk:wake quick --home "$home" --shell quick-a --packet "$packet" --model openai-codex/gpt-5.6-sol --work-dir "$work_dir" --yes

  [ "$status" -eq 0 ]
  [[ "$output" == *"launching fresh wake in shell quick-a"* ]]
  [[ "$output" == *"Agent wake ready"* ]]
  [[ "$output" == *"mode:    fresh"* ]]
  [[ "$output" == *"session: new-pi-session"* ]]
  [[ "$output" == *"attach:  shell attach quick-a"* ]]
  work_real=$(cd "$work_dir" && pwd -P)
  grep -q "shell run --probe-ready --ready-timeout 10 --cwd $home_real quick-a $work_real/start-quick-a.sh" "$SHELL_LOG"
  grep -q "sessions ps --all --json" "$SESSIONS_LOG"
}

@test "agent:desk:wake makes a final observation after a slow deadline-edge probe" {
  home="$BATS_TEST_TMPDIR/home"
  work_dir="$BATS_TEST_TMPDIR/wake"
  packet="$BATS_TEST_TMPDIR/packet.md"
  make_repo "$home" home
  printf 'hello packet\n' > "$packet"
  export FAKE_SESSION_CWD="$(cd "$home" && pwd -P)"
  export FAKE_SESSIONS_MODE=deadline-edge
  export FAKE_SESSIONS_DELAY=1.1

  run fold_task agent:desk:wake quick --home "$home" --shell quick-a --packet "$packet" --model openai-codex/gpt-5.6-sol --startup-timeout 1 --work-dir "$work_dir" --yes

  [ "$status" -eq 0 ]
  [[ "$output" == *"Agent wake ready"* ]]
  [[ "$output" == *"session: new-pi-session"* ]]
  [ "$(cat "$SESSIONS_CALLS")" -ge 3 ]
}

@test "agent:desk:wake rejects an excessive shell readiness timeout" {
  home="$BATS_TEST_TMPDIR/home"
  packet="$BATS_TEST_TMPDIR/packet.md"
  make_repo "$home" home
  printf 'hello packet\n' > "$packet"

  run fold_task agent:desk:wake quick --home "$home" --shell quick-a --packet "$packet" --model openai-codex/gpt-5.6-sol --shell-ready-timeout 99999999999999999999

  [ "$status" -ne 0 ]
  [[ "$output" == *"--shell-ready-timeout must be an integer from 1 to 300"* ]]
  [ ! -e "$SHELL_RUN_MARKER" ]
}

@test "agent:desk:wake stops when shell readiness fails before Pi launch" {
  home="$BATS_TEST_TMPDIR/home"
  packet="$BATS_TEST_TMPDIR/packet.md"
  make_repo "$home" home
  printf 'hello packet\n' > "$packet"
  export FAKE_SESSION_CWD="$(cd "$home" && pwd -P)"
  export SHELL_RUN_MODE=fail

  run fold_task agent:desk:wake quick --home "$home" --shell quick-a --packet "$packet" --model openai-codex/gpt-5.6-sol --shell-ready-timeout 2 --yes

  [ "$status" -ne 0 ]
  [[ "$output" == *"probe did not execute"* ]]
  grep -q 'shell run --probe-ready --ready-timeout 2' "$SHELL_LOG"
  [ ! -e "$SHELL_RUN_MARKER" ]
  [ "$(cat "$SESSIONS_CALLS")" -eq 1 ]
}

@test "agent:desk:wake rejects a running shell without a new Pi process" {
  home="$BATS_TEST_TMPDIR/home"
  work_dir="$BATS_TEST_TMPDIR/wake"
  packet="$BATS_TEST_TMPDIR/packet.md"
  make_repo "$home" home
  printf 'hello packet\n' > "$packet"
  export FAKE_SESSION_CWD="$(cd "$home" && pwd -P)"
  export FAKE_SESSIONS_MODE=never

  run fold_task agent:desk:wake quick --home "$home" --shell quick-a --packet "$packet" --model openai-codex/gpt-5.6-sol --startup-timeout 1 --work-dir "$work_dir" --yes

  [ "$status" -ne 0 ]
  [[ "$output" == *"no new live Pi process appeared during the 1s window or final observation"* ]]
  [[ "$output" == *"line one"* ]]
}

@test "agent:desk:wake surfaces a shell that exits before Pi starts" {
  home="$BATS_TEST_TMPDIR/home"
  work_dir="$BATS_TEST_TMPDIR/wake"
  packet="$BATS_TEST_TMPDIR/packet.md"
  make_repo "$home" home
  printf 'hello packet\n' > "$packet"
  export FAKE_SESSION_CWD="$(cd "$home" && pwd -P)"
  export FAKE_SESSIONS_MODE=never
  export SHELL_STATUS_MODE=fail-after-run

  run fold_task agent:desk:wake quick --home "$home" --shell quick-a --packet "$packet" --model openai-codex/gpt-5.6-sol --startup-timeout 5 --work-dir "$work_dir" --yes

  [ "$status" -ne 0 ]
  [[ "$output" == *"agent shell exited before Pi became ready"* ]]
  [[ "$output" == *"exited (1)"* ]]
}
