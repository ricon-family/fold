#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load ../test_helper
load helpers
load shell

setup() {
  setup_desk_test
  setup_shell_mock
}

@test "agent:desk:status inspects one explicit desk without assuming singleton agent state" {
  desk="$BATS_TEST_TMPDIR/desks/quick-a"
  mkdir -p "$desk/.desk"
  printf '{"id":"quick-a"}\n' > "$desk/.desk/registry.json"
  make_repo "$desk/home" home
  make_repo "$desk/nvr" nvr
  desk_real=$(cd "$desk" && pwd -P)

  run fold_task agent:desk:status quick --desk "$desk" --shell quick-a --recent 1

  [ "$status" -eq 0 ]
  [[ "$output" == *"agent: quick"* ]]
  [[ "$output" == *"desk:  $desk_real"* ]]
  [[ "$output" == *"name: quick-a"* ]]
  [[ "$output" == *"running"* ]]
  [[ "$output" == *"== home =="* ]]
  [[ "$output" == *"== nvr =="* ]]
}

@test "agent:desk:pi-auth shows provider metadata without token values" {
  pi_dir="$BATS_TEST_TMPDIR/pi-agent"
  mkdir -p "$pi_dir"
  cat > "$pi_dir/auth.json" <<'JSON'
{
  "openai-codex": {
    "type": "SECRET_TYPE_VALUE",
    "access_token": "SECRET_ACCESS",
    "refresh": "SECRET_REFRESH",
    "accountId": "acct_123",
    "expires": 123
  },
  "huggingface": {
    "type": "api_key",
    "key": "SECRET_KEY"
  }
}
JSON
  cat > "$pi_dir/models.json" <<'JSON'
{"providers":{"openai-codex":{},"local-vllm":{}}}
JSON

  run fold_task agent:desk:pi-auth --pi-dir "$pi_dir"

  [ "$status" -eq 0 ]
  [[ "$output" == *"openai-codex"* ]]
  [[ "$output" == *"huggingface"* ]]
  [[ "$output" == *"provider_keys"* ]]
  [[ "$output" != *"SECRET_ACCESS"* ]]
  [[ "$output" != *"SECRET_REFRESH"* ]]
  [[ "$output" != *"SECRET_KEY"* ]]
  [[ "$output" != *"SECRET_TYPE_VALUE"* ]]
  [[ "$output" == *"type_key=present"* ]]
}

@test "agent:desk:smoke can fail closed when --check is set" {
  export SHELL_STATUS_MODE=fail

  run fold_task agent:desk:smoke --shell quick-missing --history-lines 2 --check

  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
  [[ "$output" == *"line two"* ]]
  [[ "$output" == *"line three"* ]]
}
