#!/usr/bin/env bash

fold_welcome_normalize_identity() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr ' ' '-'
}

fold_welcome_resident_metadata() {
  local identity_dir="$1"
  local hint="$2"
  local normalized note_path note_type github_login

  normalized=$(fold_welcome_normalize_identity "$hint")
  note_path="$identity_dir/${normalized}.md"
  [ -n "$normalized" ] && [ -f "$note_path" ] || return 1

  note_type=$(awk -F ': *' '$1 == "type" { print $2; exit }' "$note_path")
  [ "$note_type" = "agent" ] || return 1
  github_login=$(awk -F ': *' '$1 == "github_login" { print $2; exit }' "$note_path")

  printf '%s\t%s\n' "$normalized" "$github_login"
}

fold_welcome_recent_note_changes() {
  local repo_dir="$1"
  local limit="${2:-5}"
  local manifest="$repo_dir/notes/.manifest"
  local count=0
  local paths path note_id note_name commit_summary

  paths=$(git -C "$repo_dir" log -10 --format= --name-only -- notes 2>/dev/null \
    | awk 'NF && $0 != "notes/.manifest" && !seen[$0]++') || return 1

  while IFS= read -r path; do
    [ -n "$path" ] || continue
    [ "$count" -lt "$limit" ] || break

    note_id=${path#notes/}
    note_name=""
    if [ -f "$manifest" ]; then
      note_name=$(awk -F '\t' -v id="$note_id" '$1 == id { print $2; exit }' "$manifest")
    fi
    [ -n "$note_name" ] || note_name="$note_id"

    commit_summary=$(git -C "$repo_dir" log -1 --format='%h %s' -- "$path" 2>/dev/null || true)
    printf '%s\t%s\n' "$note_name" "$commit_summary"
    count=$((count + 1))
  done <<EOF
$paths
EOF
}

fold_welcome_chat_rows() {
  local identity="$1"
  local limit="${2:-5}"
  local payload

  payload=$(chat read fold --as "$identity" --peek --all --last "$limit" --json 2>/dev/null) || return 1
  printf '%s' "$payload" | jq -r --argjson limit "$limit" '
    .[:$limit][]
    | [
        (.sender // "?"),
        (.timestamp // "?"),
        ((.preview // .body // "") | gsub("[\\t\\r\\n]+"; " "))
      ]
    | @tsv
  '
}

fold_welcome_github_attention() {
  local expected_login="$1"
  local limit="${2:-5}"
  local viewer work_dir review_json authored_json issue_json combined
  local review_pid authored_pid issue_pid
  local review_ok=false authored_ok=false issue_ok=false

  viewer=$(gh api graphql -f query='query { viewer { login } }' --jq '.data.viewer.login' 2>/dev/null) || return 1
  [ -n "$viewer" ] || return 1

  if [ -n "$expected_login" ] && [ "$viewer" != "$expected_login" ]; then
    printf 'MISMATCH\t%s\t%s\n' "$viewer" "$expected_login"
    return 2
  fi

  work_dir=$(mktemp -d "${TMPDIR:-/tmp}/fold-welcome-github.XXXXXX") || return 1
  review_json="$work_dir/reviews.json"
  authored_json="$work_dir/authored.json"
  issue_json="$work_dir/issues.json"
  combined="$work_dir/attention.tsv"
  : > "$combined"

  gh search prs \
    --owner KnickKnackLabs \
    --owner ricon-family \
    --state open \
    --review-requested "$viewer" \
    --sort updated \
    --order desc \
    --limit 10 \
    --json number,title,url,repository,updatedAt \
    > "$review_json" 2>/dev/null &
  review_pid=$!

  gh search prs \
    --owner KnickKnackLabs \
    --owner ricon-family \
    --state open \
    --author "$viewer" \
    --sort updated \
    --order desc \
    --limit 10 \
    --json number,title,url,repository,updatedAt \
    > "$authored_json" 2>/dev/null &
  authored_pid=$!

  gh search issues \
    --owner KnickKnackLabs \
    --owner ricon-family \
    --state open \
    --assignee "$viewer" \
    --sort updated \
    --order desc \
    --limit 10 \
    --json number,title,url,repository,updatedAt \
    > "$issue_json" 2>/dev/null &
  issue_pid=$!

  if wait "$review_pid"; then review_ok=true; fi
  if wait "$authored_pid"; then authored_ok=true; fi
  if wait "$issue_pid"; then issue_ok=true; fi

  if [ "$review_ok" = true ]; then
    jq -r '.[] | ["Review", .repository.nameWithOwner, ("#" + (.number | tostring)), .title, .url] | @tsv' "$review_json" >> "$combined"
  fi
  if [ "$authored_ok" = true ]; then
    jq -r '.[] | ["Authored", .repository.nameWithOwner, ("#" + (.number | tostring)), .title, .url] | @tsv' "$authored_json" >> "$combined"
  fi
  if [ "$issue_ok" = true ]; then
    jq -r '.[] | ["Assigned", .repository.nameWithOwner, ("#" + (.number | tostring)), .title, .url] | @tsv' "$issue_json" >> "$combined"
  fi

  if [ "$review_ok" != true ] && [ "$authored_ok" != true ] && [ "$issue_ok" != true ]; then
    rm -rf "$work_dir"
    return 1
  fi

  printf 'META\t%s\n' "$viewer"
  awk -F '\t' -v limit="$limit" '!seen[$2 FS $3]++ { print; count++; if (count >= limit) exit }' "$combined"
  rm -rf "$work_dir"
}
