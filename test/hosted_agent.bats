#!/usr/bin/env bats

load test_helper

@test "hosted agent workflow delegates headless execution through sessions" {
  workflow="$REPO_DIR/.github/workflows/agent-run.yml"
  agent_task="$REPO_DIR/.mise/tasks/agent/_default"

  grep -Fq 'mise run ci:env' "$workflow"
  grep -Fq 'mise agent' "$workflow"
  grep -Fq 'identity_shell=$(shimmer as "$AGENT")' "$agent_task"
  grep -Fq 'eval "$identity_shell"' "$agent_task"
  ! grep -Fq 'eval "$(shimmer as' "$agent_task"
  grep -Fq 'cmd=(shimmer agent --headless' "$agent_task"
  grep -Eq '^"shiv:sessions"[[:space:]]*=' "$REPO_DIR/mise.toml"
}

@test "hosted agent stops before launch when identity setup fails" {
  agent_task="$REPO_DIR/.mise/tasks/agent/_default"
  home="$BATS_TEST_TMPDIR/home"
  bin="$BATS_TEST_TMPDIR/bin"
  agent_log="$BATS_TEST_TMPDIR/agent.log"
  mkdir -p "$home" "$bin"

  cat > "$bin/shimmer" <<'SH'
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
  cat > "$bin/gh" <<'SH'
#!/usr/bin/env bash
printf 'gh called\n' >> "${AGENT_LOG:?}"
SH
  chmod +x "$bin/shimmer" "$bin/gh"

  run env \
    PATH="$bin:$PATH" \
    AGENT=quick \
    AGENT_HOME="$home" \
    AGENT_LOG="$agent_log" \
    INPUT_MESSAGE=hello \
    INPUT_MODEL=openai-codex/gpt-5.6-sol \
    RUN_TIMEOUT=30 \
    "$agent_task"

  [ "$status" -eq 23 ]
  [ ! -e "$agent_log" ]
}

@test "hosted home clone keeps credentials out of the persisted origin" {
  ci_env="$REPO_DIR/.mise/tasks/ci/env"

  grep -Fq '"$GH_BIN" repo clone "$home_repo" "$AGENT_HOME"' "$ci_env"
  grep -Fq 'remote set-url origin "$clean_remote"' "$ci_env"
  grep -Fq 'remote get-url origin' "$ci_env"
  ! grep -Fq 'x-access-token' "$ci_env"
  ! grep -Eq 'git clone.*(GH_TOKEN|github-pat)' "$ci_env"
}

@test "fold does not provision the sessions-owned Pi runtime" {
  workflow="$REPO_DIR/.github/workflows/agent-run.yml"
  ci_env="$REPO_DIR/.mise/tasks/ci/env"
  direct_pi_backend='github:[[:alnum:]_.-]+/(pi|pi-mono)(@[[:alnum:]_.-]+)?'

  # Fold owns hosted bootstrap; sessions owns Pi selection and execution.
  # Installing Pi here would create a second, potentially conflicting owner.
  grep -Eq "$direct_pi_backend" <<< 'github:example/pi'
  grep -Eq "$direct_pi_backend" <<< 'github:example/pi-mono@v1.2.3'
  ! grep -En "$direct_pi_backend" \
    "$workflow" "$ci_env" "$REPO_DIR/mise.toml"
}
