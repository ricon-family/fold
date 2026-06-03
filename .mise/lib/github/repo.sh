#!/usr/bin/env bash

GH_BIN="${GH:-gh}"
SECRETS_BIN="${SECRETS:-secrets}"

require_tool() {
  local tool
  for tool in "$@"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "ERROR: required tool not found: $tool" >&2
      exit 1
    fi
  done
}

redact_github_tokens() {
  sed -E \
    -e 's/gh[pousr]_[A-Za-z0-9_]+/[REDACTED_GITHUB_TOKEN]/g' \
    -e 's/github_pat_[A-Za-z0-9_]+/[REDACTED_GITHUB_TOKEN]/g'
}

lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

validate_agent() {
  local agent="$1"
  if [[ ! "$agent" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "ERROR: invalid agent name: $agent" >&2
    echo "Agent names may contain letters, numbers, dot, underscore, and hyphen." >&2
    exit 1
  fi
}

validate_login() {
  local login="$1"
  if [[ ! "$login" =~ ^[A-Za-z0-9-]+$ ]]; then
    echo "ERROR: invalid GitHub login: $login" >&2
    exit 1
  fi
}

validate_repo() {
  local repo="$1"
  if [[ ! "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    echo "ERROR: repo must be OWNER/REPO: $repo" >&2
    exit 1
  fi
}

normalize_permission() {
  local requested
  requested=$(lower "$1")

  case "$requested" in
    read|pull)
      printf 'pull\tread\n'
      ;;
    write|push)
      printf 'push\twrite\n'
      ;;
    triage|maintain|admin)
      printf '%s\t%s\n' "$requested" "$requested"
      ;;
    *)
      echo "ERROR: unsupported permission: $1" >&2
      echo "Use one of: read, write, triage, maintain, admin." >&2
      exit 1
      ;;
  esac
}

parse_values() {
  local values_arg="$1"
  [ -n "$values_arg" ] || return 0

  printf '%s' "$values_arg" | xargs printf '%s\n' | while IFS= read -r value; do
    [ -n "$value" ] || continue
    printf '%s\n' "$value"
  done
}

list_fold_agents() {
  local root="$1"
  (cd "$root" && mise run -q agent:list)
}

get_agent_github_login() {
  local agent="$1"
  local login
  validate_agent "$agent"

  if ! login=$("$SECRETS_BIN" get "$agent/github-username" 2>/dev/null); then
    echo "ERROR: could not read $agent/github-username" >&2
    exit 1
  fi
  if [ -z "$login" ]; then
    echo "ERROR: $agent/github-username is empty" >&2
    exit 1
  fi
  validate_login "$login"
  printf '%s\n' "$login"
}

get_agent_github_token() {
  local agent="$1"
  local token
  validate_agent "$agent"

  if ! token=$("$SECRETS_BIN" get "$agent/github-pat" 2>/dev/null); then
    echo "ERROR: could not read $agent/github-pat" >&2
    exit 1
  fi
  if [ -z "$token" ]; then
    echo "ERROR: $agent/github-pat is empty" >&2
    exit 1
  fi
  printf '%s\n' "$token"
}

repo_owner_lc() {
  local repo="$1"
  lower "${repo%%/*}"
}

repo_name_lc() {
  local repo="$1"
  lower "${repo#*/}"
}
