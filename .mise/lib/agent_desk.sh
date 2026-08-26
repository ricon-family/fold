#!/usr/bin/env bash
# Shared helpers for agent desk diagnostic mise tasks.
#
# This is a lib, not a mise task. Keep helpers read-only unless the calling
# task is explicitly mutating.

# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

AGENT_DESK_SHELL_BIN="${SHELL_BIN:-shell}"

agent_desk_validate_name() {
  local kind="$1" value="$2"
  if [[ ! "$value" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "ERROR: invalid $kind: $value" >&2
    echo "$kind may contain letters, numbers, dot, underscore, and hyphen." >&2
    exit 1
  fi
}

agent_desk_abs_path() {
  local path="$1"
  if [ -z "$path" ]; then
    return 1
  fi
  if [ ! -e "$path" ]; then
    echo "ERROR: path does not exist: $path" >&2
    exit 1
  fi
  (cd "$path" && pwd -P)
}

agent_desk_abs_file() {
  local path="$1" dir base
  if [ -z "$path" ]; then
    return 1
  fi
  if [ ! -f "$path" ]; then
    echo "ERROR: file does not exist: $path" >&2
    exit 1
  fi
  dir=$(dirname "$path")
  base=$(basename "$path")
  printf '%s/%s\n' "$(cd "$dir" && pwd -P)" "$base"
}

agent_desk_find_from_cwd() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/.desk/registry.json" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

agent_desk_resolve_desk() {
  local explicit="$1"
  if [ -n "$explicit" ]; then
    agent_desk_abs_path "$explicit"
    return 0
  fi
  if [ -n "${DESK_ROOT:-}" ] && [ -d "$DESK_ROOT" ]; then
    agent_desk_abs_path "$DESK_ROOT"
    return 0
  fi
  agent_desk_find_from_cwd || true
}

agent_desk_resolve_home() {
  local explicit="$1" desk="$2"
  if [ -n "$explicit" ]; then
    agent_desk_abs_path "$explicit"
    return 0
  fi
  if [ -n "$desk" ] && [ -d "$desk/home" ]; then
    agent_desk_abs_path "$desk/home"
    return 0
  fi
  if git -C "$PWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$PWD" rev-parse --show-toplevel
    return 0
  fi
  return 1
}

agent_desk_shell_status() {
  local shell_name="$1"
  "$AGENT_DESK_SHELL_BIN" status "$shell_name"
}

agent_desk_shell_history_tail() {
  local shell_name="$1" lines="$2"
  "$AGENT_DESK_SHELL_BIN" history "$shell_name" | tail -n "$lines"
}

agent_desk_git_status() {
  local label="$1" repo="$2" recent="$3"
  printf '\n== %s ==\n' "$label"
  printf 'path: %s\n' "$repo"
  if [ ! -d "$repo/.git" ] && ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
    printf 'not a git repo\n'
    return 0
  fi
  git -C "$repo" status --short --branch
  if [ "$recent" -gt 0 ] 2>/dev/null; then
    git -C "$repo" log --oneline --decorate -n "$recent"
  fi
}

agent_desk_list_default_repos() {
  local desk="$1"
  [ -n "$desk" ] || return 0
  [ -d "$desk" ] || return 0

  find "$desk" -maxdepth 2 -name .git -type d -print | sort | while IFS= read -r git_dir; do
    repo=${git_dir%/.git}
    label=${repo##*/}
    printf '%s=%s\n' "$label" "$repo"
  done
}

agent_desk_parse_repo_spec() {
  local spec="$1"
  if [[ "$spec" != *=* ]]; then
    echo "ERROR: repo specs must be label=path: $spec" >&2
    exit 1
  fi
  printf '%s\t%s\n' "${spec%%=*}" "${spec#*=}"
}

agent_desk_single_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\''/g")"
}

agent_desk_clean_git_config_get() {
  local repo="$1" key="$2"
  env \
    -u GIT_CONFIG_COUNT \
    -u GIT_CONFIG_PARAMETERS \
    -u GIT_CONFIG_GLOBAL \
    -u GIT_CONFIG_SYSTEM \
    -u GIT_CONFIG_NOSYSTEM \
    git -C "$repo" config --get "$key"
}

agent_desk_clean_git_config_bool() {
  local repo="$1" key="$2"
  env \
    -u GIT_CONFIG_COUNT \
    -u GIT_CONFIG_PARAMETERS \
    -u GIT_CONFIG_GLOBAL \
    -u GIT_CONFIG_SYSTEM \
    -u GIT_CONFIG_NOSYSTEM \
    git -C "$repo" config --bool --get "$key"
}

agent_desk_home_github_login() {
  local home="$1" origin path login repo

  if ! origin=$(agent_desk_clean_git_config_get "$home" remote.origin.url); then
    echo "ERROR: prepared target home has no origin remote: $home" >&2
    return 1
  fi
  case "$origin" in
    https://github.com/*) path=${origin#https://github.com/} ;;
    git@github.com:*) path=${origin#git@github.com:} ;;
    ssh://git@github.com/*) path=${origin#ssh://git@github.com/} ;;
    *)
      echo "ERROR: target home origin is not a canonical GitHub OWNER/home URL" >&2
      return 1
      ;;
  esac
  path=${path%.git}
  login=${path%%/*}
  repo=${path#*/}
  if [ -z "$login" ] || [ "$repo" != home ] || [ "$path" = "$login" ]; then
    echo "ERROR: target home origin must identify GitHub OWNER/home" >&2
    return 1
  fi
  validate_login "$login"
  printf '%s\n' "$login"
}
