#!/usr/bin/env bash

_FOLD_GITHUB_REPO_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091 # dynamic repo-local source
source "$_FOLD_GITHUB_REPO_LIB_DIR/../common.sh"

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

list_fold_agents() {
  local root="$1"
  (cd "$root" && mise run -q agent:list)
}

repo_owner_lc() {
  local repo="$1"
  lower "${repo%%/*}"
}

repo_name_lc() {
  local repo="$1"
  lower "${repo#*/}"
}
