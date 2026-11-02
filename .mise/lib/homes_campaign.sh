#!/usr/bin/env bash
# Shared helpers for fold homes:campaign and homes:smoke tasks.
#
# This is a lib, not a mise task. Self-locate via BASH_SOURCE rather than
# reading MISE_CONFIG_ROOT; agent sessions can inherit stale MCR from the
# launcher repo. See fold/notes/mise-gotchas.md.
set -euo pipefail

HOMES_CAMPAIGN_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CAMPAIGN_GIT_BIN="${GIT:-git}"
CAMPAIGN_SECRETS_BIN="${SECRETS:-secrets}"
CAMPAIGN_NOTES_BIN="${NOTES:-notes}"
CAMPAIGN_JQ_BIN="${JQ:-jq}"
export CAMPAIGN_GIT_BIN CAMPAIGN_SECRETS_BIN CAMPAIGN_NOTES_BIN CAMPAIGN_JQ_BIN

campaign_die() {
  echo "ERROR: $*" >&2
  exit 1
}

campaign_default_work_dir() {
  local name root
  name="${GIT_AUTHOR_NAME:-${USER:-agent}}"
  name=$(printf '%s' "$name" | tr -c 'A-Za-z0-9._-' '_')
  root="${HOMES_CAMPAIGN_TMP_ROOT:-/tmp}"
  printf '%s/%s.d/fold-homes-campaign/state\n' "$root" "$name"
}

campaign_validate_repo() {
  local repo="$1"
  if [[ ! "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    campaign_die "repo must be OWNER/REPO: $repo"
  fi
}

campaign_validate_auth() {
  local auth="$1"
  [ "$auth" = "-" ] && return 0
  if [[ ! "$auth" =~ ^[A-Za-z0-9._-]+$ ]]; then
    campaign_die "invalid auth name: $auth"
  fi
}

campaign_slugify_repo() {
  local repo="$1"
  printf '%s' "$repo" | sed 's#[/:]#__#g'
}

campaign_parse_values() {
  local values_arg="$1"
  [ -n "$values_arg" ] || return 0

  printf '%s' "$values_arg" | xargs printf '%s\n' | while IFS= read -r value; do
    [ -n "$value" ] || continue
    printf '%s\n' "$value"
  done
}

campaign_parse_repo_target() {
  local target="$1" repo auth

  if [[ "$target" == *:* ]]; then
    repo="${target%%:*}"
    auth="${target#*:}"
    [ -n "$auth" ] || campaign_die "repo target auth cannot be empty: $target"
  else
    repo="$target"
    auth="-"
  fi

  campaign_validate_repo "$repo"
  campaign_validate_auth "$auth"
  printf '%s\t%s\n' "$repo" "$auth"
}

campaign_get_auth_token() {
  local auth="$1" token
  [ "$auth" = "-" ] && return 0

  if ! token=$("$CAMPAIGN_SECRETS_BIN" get "$auth/github-pat" 2>/dev/null); then
    campaign_die "could not read $auth/github-pat"
  fi
  [ -n "$token" ] || campaign_die "$auth/github-pat is empty"
  printf '%s\n' "$token"
}

campaign_run_git() {
  local token="$1"
  shift

  if [ -n "$token" ]; then
    GH_TOKEN="$token" GIT_TERMINAL_PROMPT=0 "$CAMPAIGN_GIT_BIN" \
      -c credential.helper= \
      -c "credential.helper=!f() { echo username=x-access-token; echo \"password=\$GH_TOKEN\"; }; f" \
      "$@"
  else
    GIT_TERMINAL_PROMPT=0 "$CAMPAIGN_GIT_BIN" "$@"
  fi
}

campaign_require_file() {
  local path="$1" label="$2"
  if [ ! -f "$path" ]; then
    echo "ERROR: missing $label: $path" >&2
    exit 1
  fi
}

campaign_timeout_command() {
  command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null
}

campaign_notes_state() {
  local dir="$1" status timeout_bin
  if [ ! -f "$dir/notes/.manifest" ]; then
    printf 'none'
    return 0
  fi

  if timeout_bin=$(campaign_timeout_command); then
    if ! status=$(cd "$dir" && "$timeout_bin" 45 "$CAMPAIGN_NOTES_BIN" status --json 2>/dev/null); then
      printf 'status-failed'
      return 0
    fi
  elif ! status=$(cd "$dir" && "$CAMPAIGN_NOTES_BIN" status --json 2>/dev/null); then
    printf 'status-failed'
    return 0
  fi

  printf '%s/%s' \
    "$(printf '%s' "$status" | "$CAMPAIGN_JQ_BIN" -r '.encryption.status // "?"')" \
    "$(printf '%s' "$status" | "$CAMPAIGN_JQ_BIN" -r '.obfuscation.status // "?"')"
}

campaign_modules_state() {
  local dir="$1"
  if [ ! -f "$dir/.modules/config" ]; then
    printf 'none'
    return 0
  fi
  if [ ! -f "$dir/.modules/manifest" ]; then
    printf 'missing-manifest'
    return 0
  fi
  if LC_ALL=C awk '
    NF == 0 { next }
    NF != 3 && NF != 4 { bad = 1 }
    $3 !~ /^[0-9a-f]{40}$/ { bad = 1 }
    END { exit bad }
  ' "$dir/.modules/manifest" 2>/dev/null; then
    printf 'readable'
  else
    printf 'encrypted'
  fi
}

campaign_clone_state() {
  if [ -d "$1/.git" ]; then
    printf 'yes'
  else
    printf 'no'
  fi
}

campaign_resolve_work_dir() {
  local work_dir="$1"
  if [ -n "$work_dir" ]; then
    printf '%s\n' "$work_dir"
  else
    campaign_default_work_dir
  fi
}

campaign_select_filters_file() {
  local repo_filters="$1" filters_file="$2"
  campaign_parse_values "$repo_filters" | while IFS= read -r filter; do
    [ -n "$filter" ] || continue
    parsed=$(campaign_parse_repo_target "$filter")
    printf '%s\n' "${parsed%%$'\t'*}"
  done > "$filters_file"
}
