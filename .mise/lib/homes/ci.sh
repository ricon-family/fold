#!/usr/bin/env bash
# Shared helpers for fold homes:ci:* mise tasks.
#
# This is a lib, not a mise task. Self-locate via BASH_SOURCE rather than
# reading MISE_CONFIG_ROOT; agent sessions can inherit a stale MCR from the
# launcher repo. See fold/notes/mise-gotchas.md.
set -euo pipefail

HOMES_CI_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOMES_CI_LIB_ROOT="$(cd "$HOMES_CI_LIB_DIR/.." && pwd)"
# shellcheck source=.mise/lib/common.sh
source "$HOMES_CI_LIB_ROOT/common.sh"

HOMES_CI_JQ_BIN="${JQ:-jq}"
export HOMES_CI_JQ_BIN

homes_ci_die() {
  echo "ERROR: $*" >&2
  exit 1
}

homes_ci_require_tools() {
  require_tool "$GH_BIN" "$SECRETS_BIN" "$HOMES_CI_JQ_BIN" xargs sed tr grep
}

homes_ci_agent_secret_prefix() {
  local agent="$1"
  validate_agent "$agent"
  printf '%s' "$agent" | tr '[:lower:]' '[:upper:]' | sed 's/[^A-Z0-9]/_/g'
}

homes_ci_required_agent_secrets() {
  local agent="$1" prefix
  prefix=$(homes_ci_agent_secret_prefix "$agent")
  printf '%s_GITHUB_PAT\n' "$prefix"
  printf '%s_GPG_PRIVATE_KEY\n' "$prefix"
  printf '%s_EMAIL_PASSWORD\n' "$prefix"
}

homes_ci_required_secret_names() {
  local scope="$1" agent="$2"

  case "$scope" in
    agent-home)
      homes_ci_required_agent_secrets "$agent"
      printf 'PI_AUTH_JSON\n'
      ;;
    pi-auth)
      validate_agent "$agent"
      printf 'PI_AUTH_JSON\n'
      ;;
    *)
      homes_ci_die "unknown CI secret status scope: $scope"
      ;;
  esac
}

homes_ci_error_secret_name() {
  local scope="$1"
  case "$scope" in
    agent-home) printf '-' ;;
    pi-auth) printf 'PI_AUTH_JSON' ;;
    *) homes_ci_die "unknown CI secret status scope: $scope" ;;
  esac
}

homes_ci_parse_repo_target() {
  local target="$1" repo agent

  if [[ "$target" == *:* ]]; then
    repo="${target%%:*}"
    agent="${target#*:}"
    [ -n "$agent" ] || homes_ci_die "repo target agent cannot be empty: $target"
  else
    homes_ci_die "repo target must include :agent for CI secret checks: $target"
  fi

  validate_repo "$repo"
  validate_agent "$agent"
  printf '%s\t%s\n' "$repo" "$agent"
}

homes_ci_default_targets() {
  local json
  if ! json=$(cd "${MISE_CONFIG_ROOT:?MISE_CONFIG_ROOT not set}" && mise run -q agent:list --ci --json); then
    homes_ci_die "could not list CI agents"
  fi

  if ! printf '%s' "$json" | "$HOMES_CI_JQ_BIN" -e 'type == "array"' >/dev/null; then
    homes_ci_die "agent:list --json did not return an array"
  fi

  if printf '%s' "$json" | "$HOMES_CI_JQ_BIN" -e '.[] | select((.github_login // "") == "")' >/dev/null; then
    homes_ci_die "all CI agents need github_login metadata for home repo targeting"
  fi

  printf '%s' "$json" | "$HOMES_CI_JQ_BIN" -r '.[] | "\(.github_login)/home:\(.name)"'
}

homes_ci_targets_file() {
  local repo_arg="$1" out="$2" target parsed had_explicit=false

  : > "$out"
  while IFS= read -r target; do
    [ -n "$target" ] || continue
    had_explicit=true
    parsed=$(homes_ci_parse_repo_target "$target")
    printf '%s\n' "$parsed" >> "$out"
  done < <(parse_values "$repo_arg")

  if [ "$had_explicit" = "false" ]; then
    while IFS= read -r target; do
      [ -n "$target" ] || continue
      parsed=$(homes_ci_parse_repo_target "$target")
      printf '%s\n' "$parsed" >> "$out"
    done < <(homes_ci_default_targets)
  fi

  if [ ! -s "$out" ]; then
    homes_ci_die "no home repo targets found"
  fi
}

homes_ci_secret_names_file() {
  local repo="$1" agent="$2" out="$3" token

  if ! token=$("$SECRETS_BIN" get "$agent/github-pat" 2>/dev/null); then
    echo "could not read $agent/github-pat" >&2
    return 1
  fi
  if [ -z "$token" ]; then
    echo "$agent/github-pat is empty" >&2
    return 1
  fi

  if ! GH_TOKEN="$token" "$GH_BIN" secret list --repo "$repo" --json name --jq '.[].name' > "$out"; then
    unset token
    return 1
  fi
  unset token
}

homes_ci_secret_present() {
  local names_file="$1" secret="$2"
  grep -Fxq "$secret" "$names_file"
}

homes_ci_sanitize_detail() {
  redact_github_tokens | tr '\n\t' '  ' | sed 's/[[:space:]]\{1,\}/ /g; s/^ //; s/ $//' | cut -c 1-160
}

homes_ci_print_row() {
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5"
}

homes_ci_print_secret_status() {
  local targets_file="$1" scope="$2" tmp_dir="$3"
  local names_file="$tmp_dir/secrets.txt"
  local required_file="$tmp_dir/required-secrets.txt"
  local err_file="$tmp_dir/gh.err"
  local repo agent secret detail error_secret missing=0

  homes_ci_print_row Repo Agent Secret Status Detail
  while IFS=$'\t' read -r repo agent; do
    [ -n "$repo" ] || continue

    if ! homes_ci_secret_names_file "$repo" "$agent" "$names_file" 2>"$err_file"; then
      detail=$(homes_ci_sanitize_detail < "$err_file")
      [ -n "$detail" ] || detail="gh secret list failed"
      error_secret=$(homes_ci_error_secret_name "$scope")
      homes_ci_print_row "$repo" "$agent" "$error_secret" "error" "$detail"
      missing=1
      continue
    fi

    homes_ci_required_secret_names "$scope" "$agent" > "$required_file"
    while IFS= read -r secret; do
      [ -n "$secret" ] || continue
      if homes_ci_secret_present "$names_file" "$secret"; then
        homes_ci_print_row "$repo" "$agent" "$secret" "present" ""
      else
        homes_ci_print_row "$repo" "$agent" "$secret" "missing" ""
        missing=1
      fi
    done < "$required_file"
  done < "$targets_file"

  return "$missing"
}
