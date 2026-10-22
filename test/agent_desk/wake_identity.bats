#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load ../test_helper
load helpers
load shell
load identity_helpers

# Execute the rendered launcher with fixture identity and service boundaries.
setup() {
  setup_desk_test
  setup_shell_mock
  export FAKE_GITHUB_LOGIN=quick-ricon
  write_fake_gh
  write_resume_sessions
}

@test "agent:desk:wake requires an explicit model before rendering" {
  home="$BATS_TEST_TMPDIR/home"
  packet="$BATS_TEST_TMPDIR/packet.md"
  make_repo "$home" home
  printf 'hello packet\n' > "$packet"

  run fold_task agent:desk:wake quick --home "$home" --shell quick-a --packet "$packet"

  [ "$status" -eq 64 ]
  [[ "${output}${stderr:-}" == *"ERROR: --model is required"* ]]
}

@test "agent:desk:wake rejects a noncanonical home origin without printing credentials" {
  home="$BATS_TEST_TMPDIR/home"
  packet="$BATS_TEST_TMPDIR/packet.md"
  make_repo "$home" home
  git -C "$home" remote set-url origin https://secret-token@github.com/quick-ricon/home.git
  printf 'hello packet\n' > "$packet"

  run fold_task agent:desk:wake quick \
    --home "$home" \
    --shell quick-a \
    --packet "$packet" \
    --model openai-codex/gpt-5.6-sol

  [ "$status" -ne 0 ]
  [[ "$output" == *"target home origin is not a canonical GitHub OWNER/home URL"* ]]
  [[ "$output" != *"secret-token"* ]]
}

@test "agent:desk:wake defaults identity to the desk home" {
  home="$BATS_TEST_TMPDIR/home"
  work_dir="$BATS_TEST_TMPDIR/wake"
  packet="$BATS_TEST_TMPDIR/packet.md"
  make_repo "$home" home
  printf 'hello packet\n' > "$packet"
  home_real=$(cd "$home" && pwd -P)

  run fold_task agent:desk:wake quick \
    --home "$home" \
    --shell quick-a \
    --packet "$packet" \
    --model openai-codex/gpt-5.6-sol \
    --work-dir "$work_dir"

  [ "$status" -eq 0 ]
  [[ "$output" == *"identity-source: $home_real"* ]]
  [[ "$output" == *"dry-run"* ]]
  [ -x "$work_dir/start-quick-a.sh" ]
  if [ -f "$SHELL_LOG" ]; then
    ! grep -q 'shell run' "$SHELL_LOG"
  fi

  export AGENT_LOG="$BATS_TEST_TMPDIR/agent.log"
  write_target_identity_shimmer
  "$work_dir/start-quick-a.sh"

  grep -Fx "AGENT_HOME=$home_real" "$AGENT_LOG"
  grep -Fx 'MODEL=openai-codex/gpt-5.6-sol' "$AGENT_LOG"
  [ "$(wc -l < "$work_dir/start-quick-a.sh")" -le 20 ]
}

@test "agent:desk:wake binds inherited email selectors to the launcher-selected home" {
  home="$BATS_TEST_TMPDIR/home"
  work_dir="$BATS_TEST_TMPDIR/wake"
  packet="$BATS_TEST_TMPDIR/packet.md"
  agent_log="$BATS_TEST_TMPDIR/agent.log"
  make_repo "$home" home
  printf 'hello packet\n' > "$packet"
  export AGENT_LOG="$agent_log"
  export REQUIRE_LAUNCH_CONTEXT_RESET=true
  export EMAILS_CONFIG="/agents/junior/home/.emails/himalaya.toml"
  export HIMALAYA_CONFIG="/agents/brownie/home/.emails/himalaya.toml"
  export __MISE_DIFF="stale-parent-activation"

  write_target_identity_shimmer

  fold_task agent:desk:wake quick \
    --home "$home" \
    --shell quick-a \
    --packet "$packet" \
    --model openai-codex/gpt-5.6-sol \
    --work-dir "$work_dir" >/dev/null
  run "$work_dir/start-quick-a.sh"

  [ "$status" -eq 0 ]

  home_real=$(cd "$home" && pwd -P)
  grep -Fx "EMAILS_CONFIG=$home_real/.emails/himalaya.toml" "$agent_log"
  grep -Fx 'HIMALAYA_CONFIG=unset' "$agent_log"
  grep -Fx '__MISE_DIFF=unset' "$agent_log"
}

@test "agent:desk:wake keeps the selected home when activation runs elsewhere and emits no home" {
  home="$BATS_TEST_TMPDIR/home"
  identity_source="$BATS_TEST_TMPDIR/persona-source"
  work_dir="$BATS_TEST_TMPDIR/wake"
  packet="$BATS_TEST_TMPDIR/packet.md"
  make_repo "$home" home
  mkdir "$identity_source"
  printf 'hello packet\n' > "$packet"
  export AGENT_LOG="$BATS_TEST_TMPDIR/agent.log"
  export REQUIRE_LAUNCH_CONTEXT_RESET=true
  write_target_identity_shimmer

  fold_task agent:desk:wake quick \
    --home "$home" \
    --identity-source "$identity_source" \
    --shell quick-a \
    --packet "$packet" \
    --model test/model \
    --work-dir "$work_dir" >/dev/null
  run "$work_dir/start-quick-a.sh"

  [ "$status" -eq 0 ]

  home_real=$(cd "$home" && pwd -P)
  grep -Fx "CWD=$home_real" "$AGENT_LOG"
  grep -Fx "AGENT_HOME=$home_real" "$AGENT_LOG"
  grep -Fx "EMAILS_CONFIG=$home_real/.emails/himalaya.toml" "$AGENT_LOG"
}

@test "agent:desk:wake fresh and resume launchers reject a home below the Git root" {
  home="$BATS_TEST_TMPDIR/home"
  packet="$BATS_TEST_TMPDIR/packet.md"
  make_repo "$home" home
  mkdir "$home/nested"
  printf 'hello packet\n' > "$packet"
  export AGENT_LOG="$BATS_TEST_TMPDIR/agent.log"
  write_target_identity_shimmer

  for session in '' session-123; do
    work_dir="$BATS_TEST_TMPDIR/wake-$session"
    fold_task agent:desk:wake quick \
      --home "$home/nested" \
      --session "$session" \
      --shell quick-a \
      --packet "$packet" \
      --model test/model \
      --work-dir "$work_dir" >/dev/null
    run "$work_dir/start-quick-a.sh"

    [ "$status" -ne 0 ]
    [[ "$output" == *'selected home must be the Git worktree root'* ]]
    [ ! -e "$AGENT_LOG" ]
    [ ! -e "$SESSIONS_ENV_LOG" ]
  done
}

@test "agent:desk:wake replaces an activated parent persona without mutating the parent" {
  home="$BATS_TEST_TMPDIR/home"
  packet="$BATS_TEST_TMPDIR/packet.md"
  make_repo "$home" home
  printf 'hello packet\n' > "$packet"
  export AGENT_LOG="$BATS_TEST_TMPDIR/agent.log"
  setup_switching_personas

  export GIT_CONFIG_COUNT=1
  export GIT_CONFIG_KEY_0=core.editor
  export GIT_CONFIG_VALUE_0=fixture-editor
  export UNRELATED_SETTING=keep-me

  parent_exports=$("$TMPBIN/shimmer" as junior)
  eval "$parent_exports"
  unset parent_exports
  parent_persona_state="$SHIMMER_PERSONA_STATE"

  export REQUIRE_LAUNCH_CONTEXT_RESET=true
  export AGENT_HOME="/agents/junior/home"
  export AGENT_IDENTITY=junior
  export CHAT_IDENTITY=junior
  export EMAILS_CONFIG="/agents/junior/home/.emails/himalaya.toml"
  export HIMALAYA_CONFIG="/agents/junior/home/.emails/himalaya.toml"
  export GITHUB_TOKEN=junior-github-token
  export GH_CONFIG_DIR="/agents/junior/gh"
  export __MISE_DIFF=junior-activation

  home_real=$(cd "$home" && pwd -P)

  for session in '' session-123; do
    work_dir="$BATS_TEST_TMPDIR/wake-$session"
    fold_task agent:desk:wake quick \
      --home "$home" \
      --session "$session" \
      --shell quick-a \
      --packet "$packet" \
      --model test/model \
      --work-dir "$work_dir" >/dev/null

    run env \
      GIT_DIR="$BATS_TEST_TMPDIR/parent/.git" \
      GIT_WORK_TREE="$BATS_TEST_TMPDIR/parent" \
      GIT_COMMON_DIR="$BATS_TEST_TMPDIR/parent/.git" \
      "$work_dir/start-quick-a.sh"

    [ "$status" -eq 0 ]
    log="$AGENT_LOG"
    if [ -n "$session" ]; then
      log="$SESSIONS_ENV_LOG"
    fi

    grep -Fx "AGENT_HOME=$home_real" "$log"
    grep -Fx 'AGENT_IDENTITY=quick' "$log"
    grep -Fx 'CHAT_IDENTITY=quick' "$log"
    grep -Fx 'GIT_AUTHOR_NAME=quick' "$log"
    grep -Fx 'GIT_AUTHOR_EMAIL=quick@ricon.family' "$log"
    grep -Fx 'GIT_COMMITTER_NAME=quick' "$log"
    grep -Fx 'GIT_COMMITTER_EMAIL=quick@ricon.family' "$log"
    grep -Fx "GIT_SIGNING_KEY=$FIXTURE_SIGNER" "$log"
    grep -Fx 'GH_TOKEN=quick-target-token' "$log"
    grep -Fx 'EMAIL_ACCOUNTS=unset' "$log"
    grep -Fx 'EMAIL_LEGACY_IMAP_PASSWORD=unset' "$log"
    grep -Fx 'BLOBS_ACCOUNTS=unset' "$log"
    grep -Fx 'BLOBS_LEGACY_APPLICATION_KEY=unset' "$log"
    grep -Fx 'CORE_EDITOR=fixture-editor' "$log"
    grep -Fx 'UNRELATED_SETTING=keep-me' "$log"
  done

  [ "$SHIMMER_PERSONA_STATE" = "$parent_persona_state" ]
  [ "$GIT_CONFIG_COUNT" = 7 ]
  [ "$GIT_CONFIG_KEY_0" = core.editor ]
  [ "$GIT_CONFIG_VALUE_0" = fixture-editor ]
  [ "$GIT_CONFIG_KEY_1" = user.name ]
  [ "$GIT_CONFIG_VALUE_1" = junior ]
  [ "$GIT_AUTHOR_NAME" = junior ]
  [ "$GH_TOKEN" = junior-target-token ]
  [ "$EMAIL_LEGACY_IMAP_PASSWORD" = old-imap-password ]
  [ "$BLOBS_LEGACY_APPLICATION_KEY" = old-blob-key ]
}

@test "agent:desk:wake verifies configured Git identity independently of the handle" {
  home="$BATS_TEST_TMPDIR/home"
  work_dir="$BATS_TEST_TMPDIR/wake"
  packet="$BATS_TEST_TMPDIR/packet.md"
  agent_log="$BATS_TEST_TMPDIR/agent.log"
  make_repo "$home" home

  export FAKE_ACTIVE_NAME='Persona "Author"'
  export FAKE_ACTIVE_EMAIL=commits@example.test
  git -C "$home" config user.name "$FAKE_ACTIVE_NAME"
  git -C "$home" config user.email "$FAKE_ACTIVE_EMAIL"

  printf 'hello packet\n' > "$packet"
  export AGENT_LOG="$agent_log"
  write_target_identity_shimmer

  fold_task agent:desk:wake quick \
    --home "$home" \
    --shell quick-a \
    --packet "$packet" \
    --model test/model \
    --work-dir "$work_dir" >/dev/null
  run "$work_dir/start-quick-a.sh"

  [ "$status" -eq 0 ]
  grep -Fx "GIT_AUTHOR_NAME=$FAKE_ACTIVE_NAME" "$agent_log"
  grep -Fx "GIT_COMMITTER_NAME=$FAKE_ACTIVE_NAME" "$agent_log"
  grep -Fx 'GIT_AUTHOR_EMAIL=commits@example.test' "$agent_log"
  grep -Fx 'GIT_COMMITTER_EMAIL=commits@example.test' "$agent_log"
  grep -Fx 'AGENT_IDENTITY=quick' "$agent_log"
}

@test "agent:desk:wake rejects a matching handle with the wrong configured Git name" {
  home="$BATS_TEST_TMPDIR/home"
  work_dir="$BATS_TEST_TMPDIR/wake"
  packet="$BATS_TEST_TMPDIR/packet.md"
  agent_log="$BATS_TEST_TMPDIR/agent.log"
  make_repo "$home" home
  git -C "$home" config user.name 'Persona Author'
  printf 'hello packet\n' > "$packet"
  export AGENT_LOG="$agent_log"
  write_target_identity_shimmer

  fold_task agent:desk:wake quick \
    --home "$home" \
    --shell quick-a \
    --packet "$packet" \
    --model test/model \
    --work-dir "$work_dir" >/dev/null
  run "$work_dir/start-quick-a.sh"

  [ "$status" -ne 0 ]
  [[ "$output" == *'Git author name does not match the prepared target home'* ]]
  [ ! -e "$agent_log" ]
}

@test "agent:desk:wake refuses an empty prepared Git name" {
  home="$BATS_TEST_TMPDIR/home"
  work_dir="$BATS_TEST_TMPDIR/wake"
  packet="$BATS_TEST_TMPDIR/packet.md"
  make_repo "$home" home
  git -C "$home" config user.name ''
  printf 'hello packet\n' > "$packet"

  run fold_task agent:desk:wake quick \
    --home "$home" \
    --shell quick-a \
    --packet "$packet" \
    --model test/model \
    --work-dir "$work_dir"

  [ "$status" -ne 0 ]
  [[ "$output" == *'prepared target home has no Git name'* ]]
  [ ! -e "$work_dir/start-quick-a.sh" ]
}

@test "agent:desk:wake accepts the prepared fingerprint through its active long key ID" {
  home="$BATS_TEST_TMPDIR/home"
  work_dir="$BATS_TEST_TMPDIR/wake"
  packet="$BATS_TEST_TMPDIR/packet.md"
  agent_log="$BATS_TEST_TMPDIR/agent.log"
  make_repo "$home" home
  git -C "$home" config user.signingkey E290F2F77201FF5E0E3B75A65EA22CEE669F73CB
  printf 'hello packet\n' > "$packet"
  export AGENT_LOG="$agent_log"
  export FAKE_ACTIVE_SIGNING_KEY=5ea22cee669f73cb
  write_target_identity_shimmer

  fold_task agent:desk:wake quick \
    --home "$home" \
    --shell quick-a \
    --packet "$packet" \
    --model openai-codex/gpt-5.6-sol \
    --work-dir "$work_dir" >/dev/null
  run "$work_dir/start-quick-a.sh"

  [ "$status" -eq 0 ]
  [ -e "$agent_log" ]
}

@test "agent:desk:wake rejects an unrelated active signing key" {
  home="$BATS_TEST_TMPDIR/home"
  work_dir="$BATS_TEST_TMPDIR/wake"
  packet="$BATS_TEST_TMPDIR/packet.md"
  agent_log="$BATS_TEST_TMPDIR/agent.log"
  make_repo "$home" home
  git -C "$home" config user.signingkey E290F2F77201FF5E0E3B75A65EA22CEE669F73CB
  printf 'hello packet\n' > "$packet"
  export AGENT_LOG="$agent_log"
  export FAKE_ACTIVE_SIGNING_KEY=1111222233334444
  write_target_identity_shimmer

  fold_task agent:desk:wake quick \
    --home "$home" \
    --shell quick-a \
    --packet "$packet" \
    --model openai-codex/gpt-5.6-sol \
    --work-dir "$work_dir" >/dev/null
  run "$work_dir/start-quick-a.sh"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Git signing key does not match the prepared target home"* ]]
  [ ! -e "$agent_log" ]
}

@test "agent:desk:wake fails closed on a target GitHub mismatch" {
  home="$BATS_TEST_TMPDIR/home"
  work_dir="$BATS_TEST_TMPDIR/wake"
  packet="$BATS_TEST_TMPDIR/packet.md"
  agent_log="$BATS_TEST_TMPDIR/agent.log"
  make_repo "$home" home
  printf 'hello packet\n' > "$packet"
  export AGENT_LOG="$agent_log"
  export FAKE_GITHUB_LOGIN=junior-ricon
  write_target_identity_shimmer

  fold_task agent:desk:wake quick \
    --home "$home" \
    --shell quick-a \
    --packet "$packet" \
    --model openai-codex/gpt-5.6-sol \
    --work-dir "$work_dir" >/dev/null
  run "$work_dir/start-quick-a.sh"

  [ "$status" -ne 0 ]
  [[ "$output" == *"GitHub login is junior-ricon, expected quick-ricon"* ]]
  [ ! -e "$agent_log" ]
}

@test "agent:desk:wake launcher stops when identity setup fails" {
  home="$BATS_TEST_TMPDIR/home"
  work_dir="$BATS_TEST_TMPDIR/wake"
  packet="$BATS_TEST_TMPDIR/packet.md"
  agent_log="$BATS_TEST_TMPDIR/agent.log"
  make_repo "$home" home
  printf 'hello packet\n' > "$packet"
  export AGENT_LOG="$agent_log"
  cat > "$TMPBIN/shimmer" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  as)
    printf 'unset GIT_AUTHOR_NAME AGENT_HOME\n'
    exit 23
    ;;

  agent)
    printf 'agent started\n' >> "${AGENT_LOG:?}"
    ;;

  *) exit 2 ;;
esac
SH
  chmod +x "$TMPBIN/shimmer"

  fold_task agent:desk:wake quick \
    --home "$home" \
    --shell quick-a \
    --packet "$packet" \
    --model openai-codex/gpt-5.6-sol \
    --work-dir "$work_dir" >/dev/null
  run "$work_dir/start-quick-a.sh"

  [ "$status" -eq 23 ]
  [ ! -e "$agent_log" ]
}

@test "agent:desk:wake launcher rejects persona activation assigning a home" {
  home="$BATS_TEST_TMPDIR/home"
  wrong_home="$BATS_TEST_TMPDIR/wrong-home"
  work_dir="$BATS_TEST_TMPDIR/wake"
  packet="$BATS_TEST_TMPDIR/packet.md"
  agent_log="$BATS_TEST_TMPDIR/agent.log"
  make_repo "$home" home
  make_repo "$wrong_home" wrong
  printf 'hello packet\n' > "$packet"
  export FAKE_IDENTITY_HOME="$wrong_home"
  export AGENT_LOG="$agent_log"
  write_target_identity_shimmer

  fold_task agent:desk:wake quick \
    --home "$home" \
    --shell quick-a \
    --packet "$packet" \
    --model openai-codex/gpt-5.6-sol \
    --work-dir "$work_dir" >/dev/null
  run "$work_dir/start-quick-a.sh"

  [ "$status" -ne 0 ]
  [[ "$output" == *"persona activation must not assign AGENT_HOME"* ]]
  [ ! -e "$agent_log" ]
}

@test "agent:desk:wake renders relative packet paths as absolute for the launcher" {
  home="$BATS_TEST_TMPDIR/home"
  work_dir="$BATS_TEST_TMPDIR/wake"
  make_repo "$home" home
  repo_real=$(cd "$REPO_DIR" && pwd -P)

  run fold_task agent:desk:wake quick \
    --home "$home" \
    --shell quick-a \
    --packet AGENTS.md \
    --model openai-codex/gpt-5.6-sol \
    --work-dir "$work_dir"

  [ "$status" -eq 0 ]

  export AGENT_LOG="$BATS_TEST_TMPDIR/agent.log"
  write_target_identity_shimmer
  "$work_dir/start-quick-a.sh"

  grep -Fx "PACKET=$repo_real/AGENTS.md" "$AGENT_LOG"
}

@test "agent:desk:wake round-trips shell literals without executing them" {
  marker="$BATS_TEST_TMPDIR/should-not-exist"
  literal="O'Connor with spaces \$(touch '$marker')"
  home="$BATS_TEST_TMPDIR/home O'Connor"
  packet="$BATS_TEST_TMPDIR/packet O'Connor.md"
  work_dir="$BATS_TEST_TMPDIR/wake"
  make_repo "$home" home
  export FAKE_ACTIVE_NAME="$literal"
  git -C "$home" config user.name "$literal"
  printf '%s\n' "$literal" > "$packet"
  export AGENT_LOG="$BATS_TEST_TMPDIR/agent.log"
  export AGENT_MESSAGE_LOG="$BATS_TEST_TMPDIR/message"
  write_target_identity_shimmer

  fold_task agent:desk:wake quick \
    --home "$home" \
    --shell quick-a \
    --packet "$packet" \
    --title "$literal" \
    --model "$literal" \
    --work-dir "$work_dir" >/dev/null
  run "$work_dir/start-quick-a.sh"

  [ "$status" -eq 0 ]
  grep -Fx "GIT_AUTHOR_NAME=$literal" "$AGENT_LOG"
  grep -Fx "GIT_COMMITTER_NAME=$literal" "$AGENT_LOG"
  grep -Fx "MODEL=$literal" "$AGENT_LOG"

  packet_real=$(cd "$(dirname "$packet")" && pwd -P)/$(basename "$packet")
  grep -Fx "PACKET=$packet_real" "$AGENT_LOG"

  printf '[%s]\n%s' "$literal" "$literal" > "$BATS_TEST_TMPDIR/expected-message"
  cmp "$BATS_TEST_TMPDIR/expected-message" "$AGENT_MESSAGE_LOG"

  [ ! -e "$marker" ]
}

@test "agent:desk:wake preserves Shimmer refusal of ambiguous Git ownership" {
  home="$BATS_TEST_TMPDIR/home"
  packet="$BATS_TEST_TMPDIR/packet.md"
  work_dir="$BATS_TEST_TMPDIR/wake"
  make_repo "$home" home
  printf 'hello packet\n' > "$packet"
  export AGENT_LOG="$BATS_TEST_TMPDIR/agent.log"
  setup_switching_personas

  parent_exports=$("$TMPBIN/shimmer" as junior)
  eval "$parent_exports"
  unset parent_exports

  # Remove the owned user.name entry without updating its ownership record.
  export GIT_CONFIG_KEY_0=core.editor

  fold_task agent:desk:wake quick \
    --home "$home" \
    --shell quick-a \
    --packet "$packet" \
    --model test/model \
    --work-dir "$work_dir" >/dev/null
  run "$work_dir/start-quick-a.sh"

  [ "$status" -ne 0 ]
  [[ "$output" == *'Git ownership is ambiguous'* ]]
  [ ! -e "$AGENT_LOG" ]
}

@test "agent:desk:wake --session invokes sessions wake under the target identity" {
  home="$BATS_TEST_TMPDIR/home"
  work_dir="$BATS_TEST_TMPDIR/continue"
  packet="$BATS_TEST_TMPDIR/follow-up.md"
  make_repo "$home" home
  printf 'continue packet\n' > "$packet"
  export REQUIRE_LAUNCH_CONTEXT_RESET=true
  export AGENT_HOME="/agents/junior/home"
  export AGENT_IDENTITY=junior
  export CHAT_IDENTITY=junior
  export GH_TOKEN=junior-token
  export GIT_AUTHOR_NAME=junior
  export GIT_AUTHOR_EMAIL=junior@ricon.family
  export GIT_COMMITTER_NAME=junior
  export GIT_COMMITTER_EMAIL=junior@ricon.family
  export GIT_CONFIG_COUNT=1
  export GIT_CONFIG_KEY_0=user.name
  export GIT_CONFIG_VALUE_0=junior
  write_target_identity_shimmer

  fold_task agent:desk:wake quick \
    --session session-123 \
    --home "$home" \
    --shell quick-cont \
    --packet "$packet" \
    --model openai-codex/gpt-5.6-sol \
    --message "Continue the reviewed lane." \
    --work-dir "$work_dir" >/dev/null
  run "$work_dir/start-quick-cont.sh"

  [ "$status" -eq 0 ]

  home_real=$(cd "$home" && pwd -P)
  packet_real=$(cd "$(dirname "$packet")" && pwd -P)/$(basename "$packet")
  grep -F "sessions wake session-123 --model openai-codex/gpt-5.6-sol --context-file $packet_real" "$SESSIONS_LOG"
  grep -F -- "--message [agent desk wake — root handoff] Continue the reviewed lane." "$SESSIONS_LOG"
  grep -Fx "CWD=$home_real" "$SESSIONS_ENV_LOG"
  grep -Fx "AGENT_HOME=$home_real" "$SESSIONS_ENV_LOG"
  grep -Fx "EMAILS_CONFIG=$home_real/.emails/himalaya.toml" "$SESSIONS_ENV_LOG"
  grep -Fx 'HIMALAYA_CONFIG=unset' "$SESSIONS_ENV_LOG"
  grep -Fx 'AGENT_IDENTITY=quick' "$SESSIONS_ENV_LOG"
  grep -Fx 'GIT_AUTHOR_NAME=quick' "$SESSIONS_ENV_LOG"
  grep -Fx 'GIT_AUTHOR_EMAIL=quick@ricon.family' "$SESSIONS_ENV_LOG"
  grep -Fx 'GIT_COMMITTER_NAME=quick' "$SESSIONS_ENV_LOG"
  grep -Fx 'GIT_COMMITTER_EMAIL=quick@ricon.family' "$SESSIONS_ENV_LOG"
  grep -Fx 'GH_TOKEN=quick-target-token' "$SESSIONS_ENV_LOG"
  grep -Fx 'GIT_CONFIG_COUNT=4' "$SESSIONS_ENV_LOG"
}
