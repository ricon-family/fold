#!/usr/bin/env bash
# Guarded sync implementation for homes:ci:* tasks.

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
