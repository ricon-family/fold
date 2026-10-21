setup_shell_mock() {
  export SHELL_LOG="$BATS_TEST_TMPDIR/shell.log"
  export SHELL_STATUS_MODE=ok
  export SHELL_RUN_MARKER="$BATS_TEST_TMPDIR/shell-ran"
  export SHELL_EXITED_MARKER="$BATS_TEST_TMPDIR/shell-exited"
  write_fake_shell
}

write_fake_shell() {
  cat > "$TMPBIN/shell" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'shell %s\n' "$*" >> "${SHELL_LOG:?}"
case "${1:-}" in
  status)
    if [ "${SHELL_STATUS_MODE:-ok}" = fail ]; then
      echo "not found"
      exit 1
    fi
    if [ -f "${SHELL_EXITED_MARKER:?}" ]; then
      echo "exited (1)"
      exit 1
    fi

    echo "running"
    ;;

  history)
    printf 'line one\nline two\nline three\n'
    ;;

  run)
    if [ "${SHELL_RUN_MODE:-ok}" = fail ]; then
      echo "probe did not execute" >&2
      exit 1
    fi

    : > "${SHELL_RUN_MARKER:?}"
    if [ "${SHELL_STATUS_MODE:-ok}" = fail-after-run ]; then
      : > "${SHELL_EXITED_MARKER:?}"
    fi

    echo "${5:-}"
    ;;

  *)
    echo "unexpected shell command: $*" >&2
    exit 2
    ;;
esac
SH
  chmod +x "$TMPBIN/shell"
  export SHELL_BIN="$TMPBIN/shell"
}

