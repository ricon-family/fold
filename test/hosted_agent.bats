#!/usr/bin/env bats

load test_helper

@test "hosted agent workflow delegates headless execution through sessions" {
  workflow="$REPO_DIR/.github/workflows/agent-run.yml"
  agent_task="$REPO_DIR/.mise/tasks/agent/_default"

  grep -Fq 'mise run ci:env' "$workflow"
  grep -Fq 'mise agent' "$workflow"
  grep -Fq 'cmd=(shimmer agent --headless' "$agent_task"
  grep -Eq '^"shiv:sessions"[[:space:]]*=' "$REPO_DIR/mise.toml"
}

@test "hosted agent setup does not install Pi directly" {
  workflow="$REPO_DIR/.github/workflows/agent-run.yml"
  ci_env="$REPO_DIR/.mise/tasks/ci/env"

  ! grep -En 'github:[^[:space:]]+/(pi|pi-mono)@|install_pi' \
    "$workflow" "$ci_env"
}
