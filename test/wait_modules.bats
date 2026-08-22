#!/usr/bin/env bats

# Embedded Nushell snippets require literal dollar expressions.
# shellcheck disable=SC2016

bats_require_minimum_version 1.5.0

load test_helper

wait_nu() {
  cd "$REPO_DIR" && nu -c "$1"
}
export -f wait_nu

@test "waiter planning uses one Chat cursor across filter reordering" {
  run wait_nu '
    use ./lib/wait/request.nu build-request
    use ./lib/wait/waiters.nu build-waiters

    def request [senders: string] {
      build-request {
        sessions: ""
        chat: {
          room: "ops"
          identity: "alice"
          senders: $senders
          mentions: "alice"
        }
        state_dir: "/tmp/wait-state"
        timeout_seconds: "120"
      }
    }

    let executables = {chat: "chat" sessions: "sessions"}
    {
      original: (build-waiters (request "or bob or") $executables | first)
      reordered: (build-waiters (request "bob or") $executables | first)
    } | to json -r
  '

  [ "$status" -eq 0 ]
  jq -e '
    .original.kind == "chat"
    and .original.source == "chat"
    and .original.match == {
      "identity": "alice",
      "senders": ["or", "bob"],
      "mentions": ["alice"]
    }
    and .original.command[-3:] == ["--timeout", "0", "--json"]
    and (.original.command | index("--by")) == null
    and (.original.command | index("--mention")) == null
    and .original.cursor_file == .reordered.cursor_file
  ' <<< "$output"
}

@test "waiter planning preserves a hyphenated session ID" {
  run wait_nu '
    use ./lib/wait/request.nu build-request
    use ./lib/wait/waiters.nu build-waiters

    let session_id = "1eab3a38-42dd-489f-9d7e-55019e5bfa8e"
    let request = (build-request {
      sessions: $session_id
      chat: {room: "" identity: "" senders: "" mentions: ""}
      state_dir: "/tmp/wait-state"
      timeout_seconds: "120"
    })
    build-waiters $request {chat: "chat" sessions: "sessions"}
    | first
    | to json -r
  '

  [ "$status" -eq 0 ]
  jq -e '
    .command[0:3] == [
      "sessions",
      "wait-any",
      "1eab3a38-42dd-489f-9d7e-55019e5bfa8e"
    ]
  ' <<< "$output"
}

@test "coordinator preserves every result already queued" {
  run wait_nu '
    use ./lib/wait/coordinator.nu collect-ready-results

    {source: "chat:mention:alice"} | job send 0
    collect-ready-results {source: "sessions"}
    | get source
    | to json -r
  '

  [ "$status" -eq 0 ]
  [ "$output" = '["sessions","chat:mention:alice"]' ]
}

@test "coordinator returns an expired wall-clock deadline immediately" {
  export TIMEOUT_STATE_DIR="$BATS_TEST_TMPDIR/timeout-state"

  run wait_nu '
    use ./lib/wait/coordinator.nu run-waiters

    run-waiters [] $env.TIMEOUT_STATE_DIR {
      deadline: ((date now) - 1sec)
      seconds: 300
    } | to json -r
  '

  [ "$status" -eq 0 ]
  jq -e '
    .exit_code == 0
    and .events == [{
      "source": "wait",
      "cursor_file": null,
      "exit_code": 124,
      "records": [{"event": "timeout", "timeout_seconds": 300}],
      "stderr": ""
    }]
  ' <<< "$output"
}

@test "coordinator prefers an already-queued source at the deadline" {
  export SOURCE_AT_DEADLINE_STATE_DIR="$BATS_TEST_TMPDIR/source-at-deadline-state"

  run wait_nu '
    use ./lib/wait/coordinator.nu run-waiters

    {
      source: "sessions"
      cursor_file: "/tmp/sessions.json"
      stdout: "{\"event\":\"turn.settled\",\"events\":[]}"
      stderr: ""
      exit_code: 0
    } | job send 0

    run-waiters [] $env.SOURCE_AT_DEADLINE_STATE_DIR {
      deadline: ((date now) - 1sec)
      seconds: 300
    } | to json -r
  '

  [ "$status" -eq 0 ]
  jq -e '
    .exit_code == 0
    and .events == [{
      "source": "sessions",
      "cursor_file": "/tmp/sessions.json",
      "exit_code": 0,
      "records": [{"event": "turn.settled", "events": []}],
      "stderr": ""
    }]
  ' <<< "$output"
}
