#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load test_helper

setup() {
  STATE_DIR="$BATS_TEST_TMPDIR/state"
  TMPBIN="$BATS_TEST_TMPDIR/bin"
  SLOW_PID_FILE="$BATS_TEST_TMPDIR/slow.pid"
  START_FIFO="$BATS_TEST_TMPDIR/slow-started.fifo"
  HOLD_FIFO="$BATS_TEST_TMPDIR/slow-hold.fifo"
  mkdir -p "$TMPBIN"
  mkfifo "$START_FIFO" "$HOLD_FIFO"
  export SLOW_PID_FILE START_FIFO HOLD_FIFO

  cat > "$TMPBIN/fast-sessions" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
exec 3<> "$START_FIFO"
IFS= read -r -t 2 _ <&3 || exit 91
printf '%s\n' '{"event":"turn.settled","events":[{"session_id":"alpha","text":"done"}]}'
SH

  cat > "$TMPBIN/slow-chat" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$$" > "$SLOW_PID_FILE"
exec 3<> "$START_FIFO"
printf 'started\n' >&3
exec 4<> "$HOLD_FIFO"
IFS= read -r -t 2 _ <&4 || exit 92
SH

  chmod +x "$TMPBIN/fast-sessions" "$TMPBIN/slow-chat"
}

teardown() {
  if [ -f "$SLOW_PID_FILE" ]; then
    slow_pid=$(cat "$SLOW_PID_FILE")
    if kill -0 "$slow_pid" 2>/dev/null; then
      if ! kill "$slow_pid" 2>/dev/null; then
        kill -0 "$slow_pid" 2>/dev/null && return 1
      fi
    fi
  fi
}

process_is_dead() {
  local pid=$1
  local attempt=0
  while kill -0 "$pid" 2>/dev/null && [ "$attempt" -lt 20 ]; do
    sleep 0.01
    attempt=$((attempt + 1))
  done
  ! kill -0 "$pid" 2>/dev/null
}

@test "wait help shows Sessions, Chat, and combined examples" {
  run fold_task wait --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"Wait across Sessions"* ]]
  [[ "$output" == *"Wait for either Chat match"* ]]
  [[ "$output" == *"Wait across Chat and Sessions"* ]]
}

@test "wait rejects a request without a source" {
  run fold_task wait --state-dir "$STATE_DIR"

  [ "$status" -eq 2 ]
  [[ "$output" == *"provide at least one --session or --chat source"* ]]
  [ ! -e "$STATE_DIR" ]
}

@test "wait requires an explicit identity for Chat" {
  run fold_task wait --chat ops --state-dir "$STATE_DIR"

  [ "$status" -eq 2 ]
  [[ "$output" == *"--chat requires an explicit --as identity"* ]]
  [ ! -e "$STATE_DIR" ]
}

@test "wait rejects Chat options without a room" {
  run fold_task wait --from or --state-dir "$STATE_DIR"

  [ "$status" -eq 2 ]
  [[ "$output" == *"--as, --from, and --mention require --chat"* ]]
  [ ! -e "$STATE_DIR" ]
}

@test "wait requires an independent state directory" {
  run fold_task wait --session alpha

  [ "$status" -eq 2 ]
  [[ "$output" == *"--state-dir is required"* ]]
}

@test "wait rejects a state path that is not a directory" {
  printf 'not a directory\n' > "$STATE_DIR"

  run fold_task wait --session alpha --state-dir "$STATE_DIR"

  [ "$status" -eq 2 ]
  [[ "$output" == *"--state-dir must be a directory"* ]]
}

@test "wait rejects malformed and negative timeouts" {
  run fold_task wait \
    --session alpha \
    --state-dir "$STATE_DIR" \
    --timeout soon

  [ "$status" -eq 2 ]
  [[ "$output" == *"--timeout must be a non-negative integer"* ]]
  [ ! -e "$STATE_DIR" ]

  run fold_task wait \
    --session alpha \
    --state-dir "$STATE_DIR" \
    --timeout -1

  [ "$status" -eq 2 ]
  [[ "$output" == *"--timeout must be a non-negative integer"* ]]
  [ ! -e "$STATE_DIR" ]
}

@test "wait returns the first source event and stops the quiet sibling" {
  export SESSIONS="$TMPBIN/fast-sessions"
  export CHAT="$TMPBIN/slow-chat"

  run fold_task wait \
    --session alpha \
    --chat ops \
    --as alice \
    --from or \
    --state-dir "$STATE_DIR" \
    --timeout 5

  [ "$status" -eq 0 ]
  [ -d "$STATE_DIR" ]
  [ -f "$SLOW_PID_FILE" ]
  jq -e '
    .source == "sessions"
    and .exit_code == 0
    and .records[0].event == "turn.settled"
    and .records[0].events[0].text == "done"
  ' <<< "$output"

  slow_pid=$(cat "$SLOW_PID_FILE")
  process_is_dead "$slow_pid"
}

@test "wait restarts one Chat child and applies sender-or-mention rules" {
  CHAT_CALLS="$BATS_TEST_TMPDIR/chat-calls"
  export CHAT_CALLS
  cat > "$TMPBIN/chat-sequence" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
calls=0
if [ -f "$CHAT_CALLS" ]; then
  calls=$(cat "$CHAT_CALLS")
fi
calls=$((calls + 1))
printf '%s\n' "$calls" > "$CHAT_CALLS"

if [ "$calls" -eq 1 ]; then
  printf '%s\n' '{"sender":"bob","timestamp":"2026-08-22 17:00","body":"hello @alice-helper"}'
  exit 0
fi

printf '%s\n' \
  '{"sender":"or","timestamp":"2026-08-22 17:01","body":"plain update"}' \
  '{"sender":"bob","timestamp":"2026-08-22 17:02","body":"hello @alice!"}' \
  '{"sender":"quick","timestamp":"2026-08-22 17:03","body":"unrelated"}'
SH
  chmod +x "$TMPBIN/chat-sequence"
  export CHAT="$TMPBIN/chat-sequence"

  run fold_task wait \
    --chat ops \
    --as alice \
    --from or \
    --mention alice \
    --state-dir "$STATE_DIR" \
    --timeout 5

  [ "$status" -eq 0 ]
  [ "$(cat "$CHAT_CALLS")" -eq 2 ]
  jq -e '
    .source == "chat"
    and .exit_code == 0
    and (.records | length) == 2
    and .records[0].sender == "or"
    and .records[0].body == "plain update"
    and .records[1].sender == "bob"
    and .records[1].body == "hello @alice!"
  ' <<< "$output"
}

@test "wait returns a structured source failure" {
  cat > "$TMPBIN/failing-sessions" <<'SH'
#!/usr/bin/env bash
printf 'source exploded\n' >&2
exit 42
SH
  chmod +x "$TMPBIN/failing-sessions"
  export SESSIONS="$TMPBIN/failing-sessions"

  run --separate-stderr fold_task wait \
    --session alpha \
    --state-dir "$STATE_DIR" \
    --timeout 5

  [ "$status" -eq 42 ]
  jq -e '
    .source == "sessions"
    and .exit_code == 42
    and .records == []
    and (.stderr | contains("source exploded"))
  ' <<< "$output"
}

@test "wait reports a missing source executable" {
  export SESSIONS="$TMPBIN/missing-sessions"

  run -127 --separate-stderr fold_task wait \
    --session alpha \
    --state-dir "$STATE_DIR" \
    --timeout 5

  [ "$status" -eq 127 ]
  jq -e '
    .source == "sessions"
    and .exit_code == 127
    and .records == []
    and (.stderr | length > 0)
  ' <<< "$output"
}

@test "wait turns malformed source JSON into a structured failure" {
  cat > "$TMPBIN/malformed-sessions" <<'SH'
#!/usr/bin/env bash
printf 'not json\n'
SH
  chmod +x "$TMPBIN/malformed-sessions"
  export SESSIONS="$TMPBIN/malformed-sessions"

  run --separate-stderr fold_task wait \
    --session alpha \
    --state-dir "$STATE_DIR" \
    --timeout 5

  [ "$status" -eq 1 ]
  jq -e '
    .source == "sessions"
    and .exit_code == 1
    and .records == []
    and (.stderr | contains("invalid JSON from sessions"))
  ' <<< "$output"
}

@test "wait rejects successful source output without a JSON record" {
  cat > "$TMPBIN/empty-sessions" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$TMPBIN/empty-sessions"
  export SESSIONS="$TMPBIN/empty-sessions"

  run --separate-stderr fold_task wait \
    --session alpha \
    --state-dir "$STATE_DIR" \
    --timeout 5

  [ "$status" -eq 1 ]
  jq -e '
    .source == "sessions"
    and .exit_code == 1
    and .records == []
    and (.stderr | contains("exited successfully without a JSON record"))
  ' <<< "$output"
}
