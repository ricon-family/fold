#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031 # BATS intentionally isolates each test in a subshell.

bats_require_minimum_version 1.5.0

load test_helper

setup() {
  TMPBIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$TMPBIN"
  export TMPBIN
  write_mock_issue_gh
}

write_mock_issue_gh() {
  local path="$TMPBIN/gh"
  cat > "$path" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "issue" ] && [ "${2:-}" = "view" ]; then
  issue="${3:?issue required}"
  version="${MOCK_ISSUE_VERSION:-1}"

  wants_json=false
  wants_comments=false
  for arg in "$@"; do
    [ "$arg" != "--json" ] || wants_json=true
    [ "$arg" != "--comments" ] || wants_comments=true
  done

  if [ "$wants_json" = "true" ]; then
    if [ "$version" = "2" ]; then
      comments='[{"author":{"login":"or"},"body":"first"},{"author":{"login":"x1f9"},"body":"second"}]'
    else
      comments='[{"author":{"login":"or"},"body":"first"}]'
    fi
    printf '{"number":%s,"title":"Mock issue %s v%s","state":"OPEN","updatedAt":"2026-06-22T00:00:0%sZ","url":"https://github.com/ricon-family/ricon-pi/issues/%s","author":{"login":"x1f9"},"body":"body v%s","comments":%s}\n' \
      "$issue" "$issue" "$version" "$version" "$issue" "$version" "$comments"
    exit 0
  fi

  if [ "$wants_comments" = "true" ]; then
    printf 'comments for issue #%s v%s\n' "$issue" "$version"
    exit 0
  fi
fi

printf 'unexpected gh invocation: %s\n' "$*" >&2
exit 2
SH
  chmod +x "$path"
  export GH="$path"
}

@test "github:issues:status renders selected issues" {
  export MOCK_ISSUE_VERSION=1

  run fold_task github:issues:status --repo ricon-family/ricon-pi --issues 13,14

  [ "$status" -eq 0 ]
  [[ "$output" == *"repo: ricon-family/ricon-pi"* ]]
  [[ "$output" == *"#13 Mock issue 13 v1"* ]]
  [[ "$output" == *"#14 Mock issue 14 v1"* ]]
  [[ "$output" == *"comments: 1"* ]]
}

@test "github:issues:baseline records current issue state" {
  state_dir="$BATS_TEST_TMPDIR/state"
  export MOCK_ISSUE_VERSION=1

  run fold_task github:issues:baseline --repo ricon-family/ricon-pi --issues 13 --state-dir "$state_dir"

  [ "$status" -eq 0 ]
  [[ "$output" == *"baseline reset for #13 (Mock issue 13 v1)"* ]]
  [ -f "$state_dir/issue-13.sha" ]
  [ -f "$state_dir/issue-13.json" ]
  grep -q '"title":"Mock issue 13 v1"' "$state_dir/issue-13.json"
}

@test "github:issues:watch returns on first update" {
  state_dir="$BATS_TEST_TMPDIR/state"
  export MOCK_ISSUE_VERSION=1
  fold_task github:issues:baseline --repo ricon-family/ricon-pi --issues 13 --state-dir "$state_dir"

  export MOCK_ISSUE_VERSION=2
  run fold_task github:issues:watch --repo ricon-family/ricon-pi --issues 13 --state-dir "$state_dir" --watch-seconds 1 --sleep-seconds 1

  [ "$status" -eq 0 ]
  [[ "$output" == *"Behavior: return on first update"* ]]
  [[ "$output" == *"update detected on #13 (Mock issue 13 v2)"* ]]
  [[ "$output" == *"comments for issue #13 v2"* ]]
  [[ "$output" == *"returning after update"* ]]
  grep -q '"title":"Mock issue 13 v2"' "$state_dir/issue-13.json"
}

@test "github:issues:watch baselines missing state without reporting an update" {
  state_dir="$BATS_TEST_TMPDIR/state"
  export MOCK_ISSUE_VERSION=1

  run fold_task github:issues:watch --repo ricon-family/ricon-pi --issues 13 --state-dir "$state_dir" --watch-seconds 1 --sleep-seconds 1

  [ "$status" -eq 0 ]
  [[ "$output" == *"baseline #13 (Mock issue 13 v1)"* ]]
  [[ "$output" == *"watch complete; no updates detected"* ]]
  [ -f "$state_dir/issue-13.sha" ]
}

@test "github:issues:watch rejects zero sleep seconds" {
  state_dir="$BATS_TEST_TMPDIR/state"
  export MOCK_ISSUE_VERSION=1

  run fold_task github:issues:watch --repo ricon-family/ricon-pi --issues 13 --state-dir "$state_dir" --watch-seconds 1 --sleep-seconds 0

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: --sleep-seconds must be at least 1 second: 0"* ]]
}

@test "github:issues:snapshot writes JSON and text artifacts" {
  out_dir="$BATS_TEST_TMPDIR/snapshot"
  export MOCK_ISSUE_VERSION=2

  run fold_task github:issues:snapshot --repo ricon-family/ricon-pi --issues 13,14 --out-dir "$out_dir"

  [ "$status" -eq 0 ]
  [[ "$output" == *"snapshotted #13 -> $out_dir/issue-13.json"* ]]
  [[ "$output" == *"snapshotted #14 -> $out_dir/issue-14.json"* ]]
  [ -f "$out_dir/issue-13.json" ]
  [ -f "$out_dir/issue-13.txt" ]
  grep -q 'Mock issue 13 v2' "$out_dir/issue-13.json"
  grep -q 'comments for issue #13 v2' "$out_dir/issue-13.txt"
}
