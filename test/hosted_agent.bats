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
