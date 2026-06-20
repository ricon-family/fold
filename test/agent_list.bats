#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load test_helper

setup() {
  if [ ! -f "$REPO_DIR/notes/baby-joel.md" ]; then
    skip "fold readable notes are locked"
  fi
}

@test "agent:list preserves line-oriented CI roster" {
  run fold_task agent:list --ci
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | head -n 1)" = "baby-joel" ]
  [[ "$output" == *$'\nzeke' ]]
}

@test "agent:list --json emits explicit GitHub logins" {
  run fold_task agent:list --json --ci
  [ "$status" -eq 0 ]

  AGENT_LIST_JSON="$output" python3 - <<'PY'
import json
import os

records = json.loads(os.environ["AGENT_LIST_JSON"])
by_name = {record["name"]: record for record in records}
assert by_name["baby-joel"]["github_login"] == "baby-joel"
assert by_name["zeke"]["github_login"] == "zeke-ricon"
assert all(record["ci"] is True for record in records)
PY
}
