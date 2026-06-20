#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load test_helper

setup() {
  WORKBENCH="$BATS_TEST_TMPDIR/workbench"
  mkdir -p "$WORKBENCH"
}

make_file_root() {
  local root="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$root/src" "$root/.git" "$root/secrets"
  printf '# Demo\n' > "$root/README.md"
  printf '#!/usr/bin/env bash\necho hi\n' > "$root/src/run.sh"
  printf 'ignored\n' > "$root/.git/config"
  printf 'nope\n' > "$root/secrets/token.txt"
  printf '\0binary\n' > "$root/blob.bin"
  printf '%s\n' "$root"
}

@test "analysis:workbench:init creates standard artifact directories" {
  run fold_task analysis:workbench:init --workbench "$WORKBENCH"

  [ "$status" -eq 0 ]
  [ -d "$WORKBENCH/artifacts/files" ]
  [ -d "$WORKBENCH/artifacts/sessions" ]
  [ -d "$WORKBENCH/artifacts/text" ]
  [ -d "$WORKBENCH/artifacts/drones" ]
  [ -d "$WORKBENCH/config" ]
  [ -d "$WORKBENCH/logs" ]
}

@test "analysis files manifest, estimate, and pack selected text files" {
  root="$(make_file_root)"

  run fold_task analysis:files:manifest \
    --workbench "$WORKBENCH" \
    --root "$root" \
    --include 'README.md' \
    --include 'src/*.sh'

  [ "$status" -eq 0 ]
  manifest="$WORKBENCH/artifacts/files/manifest.tsv"
  skipped="$WORKBENCH/artifacts/files/manifest.skipped.tsv"
  [ -f "$manifest" ]
  [ -f "$skipped" ]
  grep -q $'repo\t' "$manifest"
  grep -q 'README.md' "$manifest"
  grep -q 'src/run.sh' "$manifest"
  ! grep -q 'secrets/token.txt' "$manifest"
  ! grep -q '.git/config' "$manifest"

  run fold_task analysis:files:estimate --workbench "$WORKBENCH"
  [ "$status" -eq 0 ]
  grep -q 'Rough tokens' "$WORKBENCH/artifacts/files/estimate.md"

  run fold_task analysis:files:pack --workbench "$WORKBENCH"
  [ "$status" -eq 0 ]
  grep -q '===== FILE repo/README.md =====' "$WORKBENCH/artifacts/files/corpus.txt"
  grep -q '===== FILE repo/src/run.sh =====' "$WORKBENCH/artifacts/files/corpus.txt"

  all_files_workbench="$BATS_TEST_TMPDIR/all-files-workbench"
  run fold_task analysis:files:manifest \
    --workbench "$all_files_workbench" \
    --root "$root"

  [ "$status" -eq 0 ]
  grep -q 'README.md' "$all_files_workbench/artifacts/files/manifest.tsv"
  grep -q 'src/run.sh' "$all_files_workbench/artifacts/files/manifest.tsv"
  ! grep -q '.git/config' "$all_files_workbench/artifacts/files/manifest.tsv"
  ! grep -q 'blob.bin' "$all_files_workbench/artifacts/files/manifest.tsv"
}

@test "analysis:text:grep-context requires excerpt acknowledgement" {
  root="$(make_file_root)"
  fold_task analysis:files:manifest \
    --workbench "$WORKBENCH" \
    --root "$root" \
    --include 'README.md' >/dev/null

  run fold_task analysis:text:grep-context \
    --workbench "$WORKBENCH" \
    --pattern 'Demo'

  [ "$status" -ne 0 ]
  [[ "$output" == *"--allow-excerpts"* ]]

  run fold_task analysis:text:grep-context \
    --workbench "$WORKBENCH" \
    --pattern 'Demo' \
    --allow-excerpts

  [ "$status" -eq 0 ]
  grep -q 'Demo' "$WORKBENCH/artifacts/text/grep-context.md"
}

write_session_metadata() {
  local session_file="$BATS_TEST_TMPDIR/session.jsonl"
  cat > "$session_file" <<'JSONL'
{"type":"session","timestamp":"2026-06-19T00:00:00Z","cwd":"/tmp/demo"}
{"type":"message","timestamp":"2026-06-19T00:00:01Z","message":{"role":"user","content":[{"type":"text","text":"private user text"}]}}
{"type":"message","timestamp":"2026-06-19T00:00:10Z","message":{"role":"assistant","usage":{"input":10},"content":[{"type":"toolCall","id":"call-1","name":"bash","arguments":{"command":"git status && mise run test"}}]}}
{"type":"message","timestamp":"2026-06-19T00:00:11Z","message":{"role":"toolResult","toolCallId":"call-1","toolName":"bash","isError":false,"content":[{"type":"text","text":"Command exited with code 1\nprivate output text"}]}}
{"type":"message","timestamp":"2026-06-19T00:00:20Z","message":{"role":"assistant","usage":{"input":10},"content":[{"type":"toolCall","id":"call-2","name":"read","arguments":{"path":"/tmp/private/path.txt"}}]}}
JSONL

  mkdir -p "$WORKBENCH/artifacts/sessions"
  cat > "$WORKBENCH/artifacts/sessions/list.json" <<JSON
[
  {
    "session_id": "abc12345-0000-0000-0000-000000000000",
    "project": "demo/home",
    "name": "demo-session",
    "model": "gpt-test",
    "first_timestamp": "2026-06-19T00:00:00Z",
    "last_timestamp": "2026-06-19T00:00:20Z",
    "total_entries": 5,
    "user_messages": 1,
    "assistant_messages": 2,
    "filepath": "$session_file"
  }
]
JSON
  cat > "$WORKBENCH/artifacts/sessions/usage.json" <<'JSON'
{
  "sessions": [
    {
      "session_id": "abc12345-0000-0000-0000-000000000000",
      "project": "demo/home",
      "name": "demo-session",
      "first_timestamp": "2026-06-19T00:00:00Z",
      "last_timestamp": "2026-06-19T00:00:20Z",
      "totals": {
        "calls": 2,
        "input": 100,
        "output": 50,
        "cacheRead": 0,
        "totalTokens": 150,
        "cost": {"total": 0.01}
      }
    }
  ]
}
JSON
}

@test "analysis sessions rank and structure do not emit transcript text" {
  write_session_metadata

  run fold_task analysis:sessions:rank --workbench "$WORKBENCH" --inspect-limit 1
  [ "$status" -eq 0 ]
  grep -q 'abc12345' "$WORKBENCH/artifacts/sessions/rank.tsv"
  grep -q 'abc12345-0000-0000-0000-000000000000' "$WORKBENCH/artifacts/sessions/inspect-candidates.txt"

  run fold_task analysis:sessions:structure --workbench "$WORKBENCH"
  [ "$status" -eq 0 ]
  grep -q 'failure/retry-heavy\|metadata-baseline\|git/gh-heavy' "$WORKBENCH/artifacts/sessions/structure.tsv"
  ! grep -R 'private user text' "$WORKBENCH/artifacts/sessions" "$WORKBENCH/artifacts/sessions-structure.md"
  ! grep -R 'private output text' "$WORKBENCH/artifacts/sessions" "$WORKBENCH/artifacts/sessions-structure.md"
  ! grep -R '/tmp/private/path.txt' "$WORKBENCH/artifacts/sessions" "$WORKBENCH/artifacts/sessions-structure.md"
  ! grep -R 'git status' "$WORKBENCH/artifacts/sessions" "$WORKBENCH/artifacts/sessions-structure.md"
}
