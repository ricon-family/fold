#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load test_helper

setup() {
  TMPBIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$TMPBIN"

  export CHAT_ARGS_LOG="$BATS_TEST_TMPDIR/chat-args.log"
  export CHAT_BODY_LOG="$BATS_TEST_TMPDIR/chat-body.log"
  export CHAT="$TMPBIN/chat"
  export COMMENT_CHAT_CHANNEL="review"
  export COMMENT_CHAT_AS="or"
  export COMMENTS_CONTEXT_JSON='{"file":"/tmp/review.md","directive":{"range":{"start":{"line":7}}}}'

  cat > "$CHAT" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "${CHAT_ARGS_LOG:?}"
cat > "${CHAT_BODY_LOG:?}"
BASH
  chmod +x "$CHAT"
}

@test "comment sends an argument with directive location through chat" {
  run fold_task comment "Please clarify this paragraph."

  [ "$status" -eq 0 ]
  [ "$(cat "$CHAT_ARGS_LOG")" = $'send\n--chat\nreview\n--as\nor\n--force' ]
  [ "$(cat "$CHAT_BODY_LOG")" = $'From /tmp/review.md:8\n\nPlease clarify this paragraph.' ]
}

@test "comment reads its message from stdin" {
  run bash -c 'printf "Please shorten this section.\n" | fold_task comment'

  [ "$status" -eq 0 ]
  [ "$(cat "$CHAT_BODY_LOG")" = $'From /tmp/review.md:8\n\nPlease shorten this section.' ]
}

@test "comment rejects dispatch without directive context" {
  unset COMMENTS_CONTEXT_JSON

  run fold_task comment "message"

  [ "$status" -eq 1 ]
  [[ "$output" == *"COMMENTS_CONTEXT_JSON is required; run through comments dispatch"* ]]
  [ ! -e "$CHAT_BODY_LOG" ]
}

@test "comment rejects malformed directive context" {
  export COMMENTS_CONTEXT_JSON='{}'

  run fold_task comment "message"

  [ "$status" -eq 1 ]
  [[ "$output" == *"COMMENTS_CONTEXT_JSON is invalid or missing file/line context"* ]]
  [ ! -e "$CHAT_BODY_LOG" ]
}
