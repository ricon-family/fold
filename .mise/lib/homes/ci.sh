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

homes_ci_required_agent_secret_sources() {
  local agent="$1" prefix
  validate_agent "$agent"
  prefix=$(homes_ci_agent_secret_prefix "$agent")
  printf '%s_GITHUB_PAT\t%s/github-pat\n' "$prefix" "$agent"
  printf '%s_GPG_PRIVATE_KEY\t%s/gpg-private-key\n' "$prefix" "$agent"
  printf '%s_EMAIL_PASSWORD\t%s/email-password\n' "$prefix" "$agent"
}

homes_ci_required_secret_names() {
  local scope="$1" agent="$2"

  case "$scope" in
    agent-home)
      homes_ci_required_agent_secrets "$agent"
      printf 'PI_AUTH_JSON\n'
      ;;
    agent-secrets)
      homes_ci_required_agent_secrets "$agent"
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
    agent-home|agent-secrets) printf '-' ;;
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

homes_ci_get_agent_github_pat() {
  local agent="$1" token

  if ! token=$("$SECRETS_BIN" get "$agent/github-pat" 2>/dev/null); then
    echo "could not read $agent/github-pat" >&2
    return 1
  fi
  if [ -z "$token" ]; then
    echo "$agent/github-pat is empty" >&2
    return 1
  fi
  printf '%s' "$token"
}

homes_ci_secret_names_file() {
  local repo="$1" agent="$2" out="$3" token

  if ! token=$(homes_ci_get_agent_github_pat "$agent"); then
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

homes_ci_write_secret_status() {
  local targets_file="$1" scope="$2" out="$3" tmp_dir="$4"
  local names_file="$tmp_dir/secrets.txt"
  local required_file="$tmp_dir/required-secrets.txt"
  local err_file="$tmp_dir/gh.err"
  local repo agent secret detail error_secret missing=0

  homes_ci_print_row Repo Agent Secret Status Detail > "$out"
  while IFS=$'\t' read -r repo agent; do
    [ -n "$repo" ] || continue

    if ! homes_ci_secret_names_file "$repo" "$agent" "$names_file" 2>"$err_file"; then
      detail=$(homes_ci_sanitize_detail < "$err_file")
      [ -n "$detail" ] || detail="gh secret list failed"
      error_secret=$(homes_ci_error_secret_name "$scope")
      homes_ci_print_row "$repo" "$agent" "$error_secret" "error" "$detail" >> "$out"
      missing=1
      continue
    fi

    homes_ci_required_secret_names "$scope" "$agent" > "$required_file"
    while IFS= read -r secret; do
      [ -n "$secret" ] || continue
      if homes_ci_secret_present "$names_file" "$secret"; then
        homes_ci_print_row "$repo" "$agent" "$secret" "present" "" >> "$out"
      else
        homes_ci_print_row "$repo" "$agent" "$secret" "missing" "" >> "$out"
        missing=1
      fi
    done < "$required_file"
  done < "$targets_file"

  return "$missing"
}

homes_ci_print_secret_status() {
  local targets_file="$1" scope="$2" tmp_dir="$3"
  local rows_file="$tmp_dir/secret-status.tsv" status=0

  homes_ci_write_secret_status "$targets_file" "$scope" "$rows_file" "$tmp_dir" || status=1
  cat "$rows_file"
  return "$status"
}

homes_ci_pi_auth_source_status() {
  local source="$1"

  if [ ! -f "$source" ]; then
    printf 'missing\tsource file not found\n'
    return 1
  fi
  if [ ! -s "$source" ]; then
    printf 'invalid\tsource file is empty\n'
    return 1
  fi
  if ! "$HOMES_CI_JQ_BIN" -e 'type == "object" and length > 0' "$source" >/dev/null 2>&1; then
    printf 'invalid\tsource is not a non-empty JSON object\n'
    return 1
  fi

  printf 'present\tvalid JSON object\n'
}

homes_ci_print_pi_auth_source_status() {
  local source="$1" result source_status source_detail status=0

  if ! result=$(homes_ci_pi_auth_source_status "$source"); then
    status=1
  fi
  source_status="${result%%$'\t'*}"
  source_detail="${result#*$'\t'}"
  printf 'Source\tStatus\tDetail\n'
  printf '%s\t%s\t%s\n' "$source" "$source_status" "$source_detail"
  return "$status"
}

homes_ci_normalize_secret_value() {
  local source_key="$1" value="$2"

  case "$source_key" in
    */gpg-private-key)
      if [[ "$value" == \"*\" ]]; then
        value="${value#\"}"
        value="${value%\"}"
      fi
      ;;
  esac

  printf '%s' "$value"
}

homes_ci_set_github_secret_value() {
  local repo="$1" agent="$2" secret="$3" value="$4" token

  if ! token=$(homes_ci_get_agent_github_pat "$agent"); then
    return 1
  fi

  if ! printf '%s' "$value" | GH_TOKEN="$token" "$GH_BIN" secret set "$secret" --repo "$repo" >/dev/null; then
    unset token value
    return 1
  fi

  unset token value
}

homes_ci_set_github_secret_file() {
  local repo="$1" agent="$2" secret="$3" file="$4" token

  if ! token=$(homes_ci_get_agent_github_pat "$agent"); then
    return 1
  fi

  if ! GH_TOKEN="$token" "$GH_BIN" secret set "$secret" --repo "$repo" < "$file" >/dev/null; then
    unset token
    return 1
  fi

  unset token
}

homes_ci_print_sync_row() {
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5"
}

homes_ci_sync_agent_secrets() {
  local targets_file="$1" yes="$2" tmp_dir="$3"
  local names_file="$tmp_dir/synced-secrets.txt"
  local err_file="$tmp_dir/sync.err"
  local repo agent secret source_key value normalized detail status=0

  homes_ci_print_sync_row Repo Agent Secret Action Detail
  while IFS=$'\t' read -r repo agent; do
    [ -n "$repo" ] || continue

    if [ "$yes" != "true" ] && ! homes_ci_secret_names_file "$repo" "$agent" "$names_file" 2>"$err_file"; then
      detail=$(homes_ci_sanitize_detail < "$err_file")
      [ -n "$detail" ] || detail="gh secret list failed"
      homes_ci_print_sync_row "$repo" "$agent" "-" "error" "$detail"
      status=1
      continue
    fi

    while IFS=$'\t' read -r secret source_key; do
      [ -n "$secret" ] || continue

      if ! value=$("$SECRETS_BIN" get "$source_key" 2>"$err_file"); then
        detail=$(homes_ci_sanitize_detail < "$err_file")
        [ -n "$detail" ] || detail="source secret missing"
        homes_ci_print_sync_row "$repo" "$agent" "$secret" "error" "$detail"
        status=1
        continue
      fi
      if [ -z "$value" ]; then
        homes_ci_print_sync_row "$repo" "$agent" "$secret" "error" "source secret is empty"
        status=1
        continue
      fi
      normalized=$(homes_ci_normalize_secret_value "$source_key" "$value")

      if [ "$yes" != "true" ]; then
        homes_ci_print_sync_row "$repo" "$agent" "$secret" "dry-run" "source present; target checked; no GitHub secret changed"
        unset value normalized
        continue
      fi

      if ! homes_ci_set_github_secret_value "$repo" "$agent" "$secret" "$normalized" 2>"$err_file"; then
        detail=$(homes_ci_sanitize_detail < "$err_file")
        [ -n "$detail" ] || detail="gh secret set failed"
        homes_ci_print_sync_row "$repo" "$agent" "$secret" "error" "$detail"
        status=1
        unset value normalized
        continue
      fi

      if homes_ci_secret_names_file "$repo" "$agent" "$names_file" 2>"$err_file" && homes_ci_secret_present "$names_file" "$secret"; then
        homes_ci_print_sync_row "$repo" "$agent" "$secret" "synced" "verified present"
      else
        detail=$(homes_ci_sanitize_detail < "$err_file")
        [ -n "$detail" ] || detail="secret not present after sync"
        homes_ci_print_sync_row "$repo" "$agent" "$secret" "error" "$detail"
        status=1
      fi
      unset value normalized
    done < <(homes_ci_required_agent_secret_sources "$agent")
  done < "$targets_file"

  return "$status"
}

homes_ci_sync_pi_auth() {
  local targets_file="$1" source="$2" yes="$3" tmp_dir="$4"
  local names_file="$tmp_dir/pi-auth-secrets.txt"
  local err_file="$tmp_dir/pi-auth-sync.err"
  local repo agent detail status=0

  homes_ci_print_sync_row Repo Agent Secret Action Detail
  while IFS=$'\t' read -r repo agent; do
    [ -n "$repo" ] || continue

    if ! homes_ci_get_agent_github_pat "$agent" >/dev/null 2>"$err_file"; then
      detail=$(homes_ci_sanitize_detail < "$err_file")
      [ -n "$detail" ] || detail="could not read agent GitHub token"
      homes_ci_print_sync_row "$repo" "$agent" "PI_AUTH_JSON" "error" "$detail"
      status=1
      continue
    fi

    if [ "$yes" != "true" ]; then
      if homes_ci_secret_names_file "$repo" "$agent" "$names_file" 2>"$err_file"; then
        homes_ci_print_sync_row "$repo" "$agent" "PI_AUTH_JSON" "dry-run" "source valid; target checked; no GitHub secret changed"
      else
        detail=$(homes_ci_sanitize_detail < "$err_file")
        [ -n "$detail" ] || detail="gh secret list failed"
        homes_ci_print_sync_row "$repo" "$agent" "PI_AUTH_JSON" "error" "$detail"
        status=1
      fi
      continue
    fi

    if ! homes_ci_set_github_secret_file "$repo" "$agent" "PI_AUTH_JSON" "$source" 2>"$err_file"; then
      detail=$(homes_ci_sanitize_detail < "$err_file")
      [ -n "$detail" ] || detail="gh secret set failed"
      homes_ci_print_sync_row "$repo" "$agent" "PI_AUTH_JSON" "error" "$detail"
      status=1
      continue
    fi

    if homes_ci_secret_names_file "$repo" "$agent" "$names_file" 2>"$err_file" && homes_ci_secret_present "$names_file" "PI_AUTH_JSON"; then
      homes_ci_print_sync_row "$repo" "$agent" "PI_AUTH_JSON" "synced" "verified present"
    else
      detail=$(homes_ci_sanitize_detail < "$err_file")
      [ -n "$detail" ] || detail="secret not present after sync"
      homes_ci_print_sync_row "$repo" "$agent" "PI_AUTH_JSON" "error" "$detail"
      status=1
    fi
  done < "$targets_file"

  return "$status"
}
