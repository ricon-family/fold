#!/usr/bin/env bash
# Shared helpers for fold GitHub issue watch tasks.
#
# This is a lib, not a mise task. Self-locate through common.sh rather than
# reading MISE_CONFIG_ROOT; agent shells can inherit a stale MCR.

_FOLD_GITHUB_ISSUES_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091 # dynamic repo-local source
source "$_FOLD_GITHUB_ISSUES_LIB_DIR/../common.sh"

validate_issue_number() {
  local issue="$1"
  issue="${issue#\#}"
  if [[ ! "$issue" =~ ^[0-9]+$ ]]; then
    echo "ERROR: issue must be a number: $1" >&2
    exit 1
  fi
  printf '%s\n' "$issue"
}

parse_issue_numbers() {
  local issues_arg="$1"
  [ -n "$issues_arg" ] || return 0

  printf '%s' "$issues_arg" \
    | tr ',' ' ' \
    | xargs printf '%s\n' \
    | while IFS= read -r issue; do
        [ -n "$issue" ] || continue
        validate_issue_number "$issue"
      done
}

require_issue_selection() {
  local repo="$1"
  local issues="$2"

  local parsed_issues

  validate_repo "$repo"
  if [ -z "$issues" ]; then
    echo "ERROR: provide --issues <numbers>" >&2
    exit 1
  fi

  parsed_issues="$(parse_issue_numbers "$issues")"
  if [ -z "$parsed_issues" ]; then
    echo "ERROR: provide at least one issue number" >&2
    exit 1
  fi
}

validate_seconds() {
  local label="$1"
  local value="$2"

  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    echo "ERROR: $label must be a non-negative integer: $value" >&2
    exit 1
  fi
}

validate_positive_seconds() {
  local label="$1"
  local value="$2"

  validate_seconds "$label" "$value"
  if [ "$value" -lt 1 ]; then
    echo "ERROR: $label must be at least 1 second: $value" >&2
    exit 1
  fi
}

repo_slug() {
  printf '%s' "$1" | tr '/[:upper:]' '_[:lower:]' | tr -cd 'a-z0-9_.-'
}

issue_key() {
  parse_issue_numbers "$1" | paste -sd '-' -
}

default_issue_state_dir() {
  local repo="$1"
  local issues="$2"
  local tmp_root="${TMPDIR:-/tmp}"

  printf '%s/fold-github-issues-watch/%s/%s\n' \
    "${tmp_root%/}" \
    "$(repo_slug "$repo")" \
    "$(issue_key "$issues")"
}

issue_json() {
  local repo="$1"
  local issue="$2"

  "$GH_BIN" issue view "$issue" \
    --repo "$repo" \
    --json number,title,state,updatedAt,url,author,body,comments
}

issue_digest() {
  shasum -a 256 | awk '{print $1}'
}

render_issue_status() {
  jq -r '"#\(.number) \(.title)\nstate: \(.state) · updated: \(.updatedAt) · comments: \(.comments | length)\nurl: \(.url)\n"'
}

save_issue_baseline() {
  local repo="$1"
  local issue="$2"
  local state_dir="$3"
  local json
  local digest

  mkdir -p "$state_dir"
  json="$(issue_json "$repo" "$issue")"
  digest="$(printf '%s' "$json" | issue_digest)"
  printf '%s\n' "$digest" > "$state_dir/issue-$issue.sha"
  printf '%s\n' "$json" > "$state_dir/issue-$issue.json"
}
