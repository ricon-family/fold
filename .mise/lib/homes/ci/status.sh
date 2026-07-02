#!/usr/bin/env bash
# Status fact collection and rendering for homes:ci:* tasks.

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
