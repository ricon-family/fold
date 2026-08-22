#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load test_helper

wait_nu() {
  cd "$REPO_DIR" && nu -c "$1"
}
export -f wait_nu

@test "waiter cursor identity survives Chat filter reordering" {
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
          mentions: ""
        }
        state_dir: "/tmp/wait-state"
        timeout_seconds: "120"
      }
    }

    let executables = {chat: "chat" sessions: "sessions"}
    {
      original: (build-waiters (request "or bob or") $executables)
      reordered: (build-waiters (request "bob or") $executables)
    } | to json -r
  '

  [ "$status" -eq 0 ]
  [ "$(jq '.original | length' <<< "$output")" -eq 2 ]

  original_or=$(jq -r '.original[] | select(.source == "chat:from:or") | .cursor_file' <<< "$output")
  reordered_or=$(jq -r '.reordered[] | select(.source == "chat:from:or") | .cursor_file' <<< "$output")
  original_bob=$(jq -r '.original[] | select(.source == "chat:from:bob") | .cursor_file' <<< "$output")

  [ "$original_or" = "$reordered_or" ]
  [ "$original_or" != "$original_bob" ]
  jq -e 'all(.original[]; .command[-3:] == ["--timeout", "0", "--json"])' <<< "$output"
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

@test "coordinator returns a structured timeout without a wall-clock delay" {
  export WAIT_TEST_STATE_DIR="$BATS_TEST_TMPDIR/timeout-state"

  run wait_nu '
    use ./lib/wait/coordinator.nu run-waiters

    run-waiters [] $env.WAIT_TEST_STATE_DIR {duration: 1ms seconds: 0.001}
    | to json -r
  '

  [ "$status" -eq 0 ]
  jq -e '
    .exit_code == 0
    and .events == [{
      "source": "wait",
      "cursor_file": null,
      "exit_code": 124,
      "records": [{"event": "timeout", "timeout_seconds": 0.001}],
      "stderr": ""
    }]
  ' <<< "$output"
}
