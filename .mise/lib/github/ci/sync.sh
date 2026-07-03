#!/usr/bin/env bash
# Guarded sync implementation for github:ci:* tasks.

github_ci_print_sync_row() {
  printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5"
}

github_ci_sync_agent_secrets() {
  local targets_file="$1" yes="$2" tmp_dir="$3" secret_set="${4:-required}"
  local names_file="$tmp_dir/synced-secrets.txt"
  local err_file="$tmp_dir/sync.err"
  local source_file="$tmp_dir/secret-sources.tsv"
  local repo agent secret source_key value normalized detail status=0

  github_ci_print_sync_row Repo Agent Secret Action Detail
  while IFS=$'\t' read -r repo agent; do
    [ -n "$repo" ] || continue

    if [ "$yes" != "true" ] && ! github_ci_secret_names_file "$repo" "$agent" "$names_file" 2>"$err_file"; then
      detail=$(github_ci_sanitize_detail < "$err_file")
      [ -n "$detail" ] || detail="gh secret list failed"
      github_ci_print_sync_row "$repo" "$agent" "-" "error" "$detail"
      status=1
      continue
    fi

    case "$secret_set" in
      required)
        github_ci_required_agent_secret_sources "$agent" > "$source_file"
        ;;
      pat)
        github_ci_agent_pat_secret_source "$agent" > "$source_file"
        ;;
      *)
        github_ci_die "unknown CI secret sync set: $secret_set"
        ;;
    esac

    while IFS=$'\t' read -r secret source_key; do
      [ -n "$secret" ] || continue

      if ! value=$("$SECRETS_BIN" get "$source_key" 2>"$err_file"); then
        detail=$(github_ci_sanitize_detail < "$err_file")
        [ -n "$detail" ] || detail="source secret missing"
        github_ci_print_sync_row "$repo" "$agent" "$secret" "error" "$detail"
        status=1
        continue
      fi
      if [ -z "$value" ]; then
        github_ci_print_sync_row "$repo" "$agent" "$secret" "error" "source secret is empty"
        status=1
        continue
      fi
      normalized=$(github_ci_normalize_secret_value "$source_key" "$value")

      if [ "$yes" != "true" ]; then
        github_ci_print_sync_row "$repo" "$agent" "$secret" "dry-run" "source present; target checked; no GitHub secret changed"
        unset value normalized
        continue
      fi

      if ! github_ci_set_github_secret_value "$repo" "$agent" "$secret" "$normalized" 2>"$err_file"; then
        detail=$(github_ci_sanitize_detail < "$err_file")
        [ -n "$detail" ] || detail="gh secret set failed"
        github_ci_print_sync_row "$repo" "$agent" "$secret" "error" "$detail"
        status=1
        unset value normalized
        continue
      fi

      if github_ci_secret_names_file "$repo" "$agent" "$names_file" 2>"$err_file" && github_ci_secret_present "$names_file" "$secret"; then
        github_ci_print_sync_row "$repo" "$agent" "$secret" "synced" "verified present"
      else
        detail=$(github_ci_sanitize_detail < "$err_file")
        [ -n "$detail" ] || detail="secret not present after sync"
        github_ci_print_sync_row "$repo" "$agent" "$secret" "error" "$detail"
        status=1
      fi
      unset value normalized
    done < "$source_file"
  done < "$targets_file"

  return "$status"
}

github_ci_sync_pi_auth() {
  local targets_file="$1" source="$2" yes="$3" tmp_dir="$4"
  local names_file="$tmp_dir/pi-auth-secrets.txt"
  local err_file="$tmp_dir/pi-auth-sync.err"
  local repo agent detail status=0

  github_ci_print_sync_row Repo Agent Secret Action Detail
  while IFS=$'\t' read -r repo agent; do
    [ -n "$repo" ] || continue

    if [ "$yes" != "true" ]; then
      if github_ci_secret_names_file "$repo" "$agent" "$names_file" 2>"$err_file"; then
        github_ci_print_sync_row "$repo" "$agent" "PI_AUTH_JSON" "dry-run" "source valid; target checked; no GitHub secret changed"
      else
        detail=$(github_ci_sanitize_detail < "$err_file")
        [ -n "$detail" ] || detail="gh secret list failed"
        github_ci_print_sync_row "$repo" "$agent" "PI_AUTH_JSON" "error" "$detail"
        status=1
      fi
      continue
    fi

    if ! github_ci_set_github_secret_file "$repo" "$agent" "PI_AUTH_JSON" "$source" 2>"$err_file"; then
      detail=$(github_ci_sanitize_detail < "$err_file")
      [ -n "$detail" ] || detail="gh secret set failed"
      github_ci_print_sync_row "$repo" "$agent" "PI_AUTH_JSON" "error" "$detail"
      status=1
      continue
    fi

    if github_ci_secret_names_file "$repo" "$agent" "$names_file" 2>"$err_file" && github_ci_secret_present "$names_file" "PI_AUTH_JSON"; then
      github_ci_print_sync_row "$repo" "$agent" "PI_AUTH_JSON" "synced" "verified present"
    else
      detail=$(github_ci_sanitize_detail < "$err_file")
      [ -n "$detail" ] || detail="secret not present after sync"
      github_ci_print_sync_row "$repo" "$agent" "PI_AUTH_JSON" "error" "$detail"
      status=1
    fi
  done < "$targets_file"

  return "$status"
}
