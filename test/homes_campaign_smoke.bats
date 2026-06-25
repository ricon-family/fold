#!/usr/bin/env bats

load test_helper

setup() {
  TEST_TMPDIR=$(mktemp -d)
  export TEST_TMPDIR

  TMPBIN="$TEST_TMPDIR/bin"
  STATE_DIR="$TEST_TMPDIR/state"
  PASS_CLONE="$STATE_DIR/clones/pass"
  FAIL_CLONE="$STATE_DIR/clones/fail"
  export TMPBIN STATE_DIR PASS_CLONE FAIL_CLONE
  mkdir -p "$TMPBIN" "$STATE_DIR/clones"

  git init -q -b main "$PASS_CLONE"
  git init -q -b main "$FAIL_CLONE"
  git -C "$PASS_CLONE" -c user.name=fixture -c user.email=fixture@example.test -c commit.gpgsign=false commit --allow-empty -q -m initial
  git -C "$FAIL_CLONE" -c user.name=fixture -c user.email=fixture@example.test -c commit.gpgsign=false commit --allow-empty -q -m initial

  cat > "$STATE_DIR/targets.tsv" <<TSV
repo	auth	clone	branch	base
owner/pass	pass	$PASS_CLONE	campaign/test	main
owner/fail	fail	$FAIL_CLONE	campaign/test	main
TSV

  MISE_LOG="$TEST_TMPDIR/mise.log"
  SHIMMER_LOG="$TEST_TMPDIR/shimmer.log"
  export MISE_LOG SHIMMER_LOG

  cat > "$TMPBIN/mise" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'cwd=%s args=%s\n' "$PWD" "$*" >> "${MISE_LOG:?}"
case "${1:-}" in
  trust|install)
    exit 0 ;;
  run)
    if [ "${2:-}" = "agent:prepare" ]; then
      case "$PWD" in
        */fail) echo "prepare failed intentionally" >&2; exit 42 ;;
        *) echo "prepared"; exit 0 ;;
      esac
    fi ;;
esac
echo "unexpected mise invocation: $*" >&2
exit 2
SH
  chmod +x "$TMPBIN/mise"

  cat > "$TMPBIN/shimmer" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'args=%s\n' "$*" >> "${SHIMMER_LOG:?}"
if [ "${1:-}" = "as" ]; then
  printf 'export SHIMMER_AGENT=%s\n' "${2:-}"
  exit 0
fi
echo "unexpected shimmer invocation: $*" >&2
exit 2
SH
  chmod +x "$TMPBIN/shimmer"

  export MISE="$TMPBIN/mise"
  export SHIMMER="$TMPBIN/shimmer"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

@test "homes:smoke:prepare records real agent:prepare failures" {
  run fold_task homes:smoke:prepare --work-dir "$STATE_DIR"

  [ "$status" -ne 0 ]
  [[ "$output" == *"pass       PASS"* ]]
  [[ "$output" == *"fail       FAIL:42"* ]]
  grep -F $'pass\towner/pass\tPASS' "$STATE_DIR/agent-prepare-smoke.tsv"
  grep -F $'fail\towner/fail\tFAIL:42' "$STATE_DIR/agent-prepare-smoke.tsv"
  [[ "$(cat "$STATE_DIR/logs/agent-prepare-smoke/fail.log")" == *"prepare failed intentionally"* ]]
}

@test "homes:smoke:state reports module clone presence" {
  mkdir -p "$PASS_CLONE/modules/fold/.git" "$FAIL_CLONE/modules/den/.git"

  run fold_task homes:smoke:state --work-dir "$STATE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *$'agent\thome_notes\thome_modules\tden_clone\tden_notes\tfold_clone\tfold_notes'* ]]
  [[ "$output" == *$'pass\tnone\tnone\tno\tnone\tyes\tnone'* ]]
  [[ "$output" == *$'fail\tnone\tnone\tyes\tnone\tno\tnone'* ]]
}

@test "homes:smoke:summary fails when prepare results include failures" {
  cat > "$STATE_DIR/agent-prepare-smoke.tsv" <<TSV
agent	repo	status	elapsed_s	log
pass	owner/pass	PASS	1	/tmp/pass.log
fail	owner/fail	FAIL:42	1	/tmp/fail.log
TSV

  run fold_task homes:smoke:summary --work-dir "$STATE_DIR"

  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL:42"* ]]
}
