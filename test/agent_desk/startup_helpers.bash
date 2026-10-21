setup_sessions_mock() {
  export SESSIONS_LOG="$BATS_TEST_TMPDIR/sessions.log"
  export SESSIONS_CALLS="$BATS_TEST_TMPDIR/sessions-calls"
  printf '0\n' > "$SESSIONS_CALLS"

  export FAKE_SESSIONS_MODE=ready
  write_fake_sessions
}

write_fake_sessions() {
  cat > "$TMPBIN/sessions" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'sessions %s\n' "$*" >> "${SESSIONS_LOG:?}"

if [ "${1:-}" = meta ]; then
  if [ "${3:-}" != --field ]; then
    echo "unexpected sessions meta command: $*" >&2
    exit 2
  fi

  case "${4:-}" in
    .meta.agent.name)
      printf '%s\n' "${FAKE_SESSION_AGENT:-quick}"
      ;;

    .cwd)
      meta_cwd="${FAKE_SESSION_META_CWD:-${FAKE_SESSION_CWD:-}}"
      if [ -z "$meta_cwd" ]; then
        echo "missing fake session cwd" >&2
        exit 1
      fi
      printf '%s\n' "$meta_cwd"
      ;;

    *)
      echo "unexpected sessions meta field: ${4:-}" >&2
      exit 2
      ;;
  esac
  exit 0
fi

call_count=$(cat "${SESSIONS_CALLS:?}")
call_count=$((call_count + 1))
printf '%s\n' "$call_count" > "$SESSIONS_CALLS"

if [ "${1:-}" != ps ] || [ "${2:-}" != --all ] || [ "${3:-}" != --json ]; then
  echo "unexpected sessions command: $*" >&2
  exit 2
fi

if [ "${FAKE_SESSIONS_MODE:-ready}" = invalid ]; then
  printf '{not-json}\n'
  exit 0
fi
if [ "${FAKE_SESSIONS_MODE:-ready}" = fail ]; then
  echo "sessions failed intentionally" >&2
  exit 42
fi

mode="${FAKE_SESSIONS_MODE:-ready}"
if [ "$mode" = deadline-edge ] && [ "$call_count" -eq 2 ]; then
  sleep "${FAKE_SESSIONS_DELAY:-1.1}"
fi

session_ready=false
if [ -f "${SHELL_RUN_MARKER:?}" ]; then
  case "$mode" in
    ready)
      session_ready=true
      ;;

    deadline-edge)
      if [ "$call_count" -ge 3 ]; then
        session_ready=true
      fi
      ;;
  esac
fi

if [ -z "${FAKE_SESSION_CWD:-}" ]; then
  printf '[]\n'
elif [ -n "${FAKE_TARGET_SESSION_ID:-}" ]; then
  if [ "$session_ready" = true ]; then
    jq -n --arg cwd "$FAKE_SESSION_CWD" --arg id "$FAKE_TARGET_SESSION_ID" \
      '[
        {
          session_id: $id,
          status: "exited",
          cwd: $cwd,
          harness: "pi",
          pid: 101,
          process_start_id: "old-start"
        },
        {
          session_id: $id,
          status: "live",
          cwd: $cwd,
          harness: "pi",
          pid: 202,
          process_start_id: "new-start"
        }
      ]'
  else
    jq -n --arg cwd "$FAKE_SESSION_CWD" --arg id "$FAKE_TARGET_SESSION_ID" \
      '[{
        session_id: $id,
        status: "exited",
        cwd: $cwd,
        harness: "pi",
        pid: 101,
        process_start_id: "old-start"
      }]'
  fi
elif [ "$session_ready" = true ]; then
  jq -n --arg cwd "$FAKE_SESSION_CWD" \
    '[
      {
        session_id: "old-pi-session",
        status: "live",
        cwd: $cwd,
        harness: "pi",
        pid: 101,
        process_start_id: "old-start"
      },
      {
        session_id: "new-pi-session",
        status: "live",
        cwd: $cwd,
        harness: "pi",
        pid: 202,
        process_start_id: "new-start"
      }
    ]'
else
  jq -n --arg cwd "$FAKE_SESSION_CWD" \
    '[{
      session_id: "old-pi-session",
      status: "live",
      cwd: $cwd,
      harness: "pi",
      pid: 101,
      process_start_id: "old-start"
    }]'
fi
SH
  chmod +x "$TMPBIN/sessions"
  export SESSIONS_BIN="$TMPBIN/sessions"
}

