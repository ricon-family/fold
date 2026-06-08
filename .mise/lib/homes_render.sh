#!/usr/bin/env bash
# Small TSV-backed render helpers for homes:* tasks.
# Source after homes.sh so homes_json_string is available.
set -euo pipefail

homes_render_record_row() {
  local file="$1" label="$2" status="$3" detail="$4"
  printf '%s\t%s\t%s\n' "$label" "$status" "$detail" >> "$file"
}

homes_render_record_check_row() {
  local file="$1" group="$2" section="$3" label="$4" status="$5" detail="$6"
  printf '%s\t%s\t%s\t%s\t%s\n' "$group" "$section" "$label" "$status" "$detail" >> "$file"
}

homes_render_status_badge() {
  local status="$1" color_mode="$2"
  case "$status" in
    ok)
      if [ "$color_mode" = "true" ]; then gum style --foreground 35 -- "✓ ok"; else printf '✓ ok'; fi ;;
    warn)
      if [ "$color_mode" = "true" ]; then gum style --foreground 214 -- "⚠ warn"; else printf '⚠ warn'; fi ;;
    *)
      if [ "$color_mode" = "true" ]; then gum style --foreground 160 -- "✗ fail"; else printf '✗ fail'; fi ;;
  esac
}

homes_render_heading() {
  local title="$1" color_mode="$2"
  if [ "$color_mode" = "true" ]; then
    gum style --bold -- "# $title"
  else
    printf '# %s\n' "$title"
  fi
  printf '\n'
}

homes_render_status_table_stream() {
  local first_header="$1" color_mode="$2" name status detail badge
  if command -v gum >/dev/null 2>&1; then
    {
      printf '%s\tStatus\tDetail\n' "$first_header"
      while IFS=$'\t' read -r name status detail; do
        [ -n "$name" ] || continue
        badge=$(homes_render_status_badge "$status" "$color_mode")
        printf '%s\t%s\t%s\n' "$name" "$badge" "$detail"
      done
    } | gum table --print --separator $'\t' --border rounded
  else
    printf '%s\tStatus\tDetail\n' "$first_header"
    while IFS=$'\t' read -r name status detail; do
      [ -n "$name" ] || continue
      badge=$(homes_render_status_badge "$status" "$color_mode")
      printf '%s\t%s\t%s\n' "$name" "$badge" "$detail"
    done
  fi
}

homes_render_status_table() {
  local first_header="$1" file="$2" color_mode="$3"
  homes_render_status_table_stream "$first_header" "$color_mode" < "$file"
}

homes_render_table() {
  homes_render_status_table "Check" "$1" "$2"
}

homes_render_file_status() {
  local file="$1" name status detail result=ok
  while IFS=$'\t' read -r name status detail; do
    [ -n "$name" ] || continue
    if [ "$status" = fail ]; then
      printf 'fail\n'
      return 0
    fi
    [ "$status" = warn ] && result=warn
  done < "$file"
  printf '%s\n' "$result"
}

homes_render_file_has_failure() {
  [ "$(homes_render_file_status "$1")" = fail ]
}

homes_render_file_warning_count() {
  local file="$1" name status detail count=0
  while IFS=$'\t' read -r name status detail; do
    [ -n "$name" ] || continue
    [ "$status" = warn ] && count=$((count + 1))
  done < "$file"
  printf '%s\n' "$count"
}

homes_render_json_section() {
  local section="$1" file="$2" first_check=true name status detail
  printf '{"name":'; homes_json_string "$section"
  printf ',"checks":['
  while IFS=$'\t' read -r name status detail; do
    [ -n "$name" ] || continue
    if [ "$first_check" = "true" ]; then first_check=false; else printf ','; fi
    printf '{"name":'; homes_json_string "$name"
    printf ',"status":'; homes_json_string "$status"
    printf ',"detail":'; homes_json_string "$detail"
    printf '}'
  done < "$file"
  printf ']}'
}

homes_render_check_rows_section_title() {
  local group="$1" section="$2"
  if [ -z "$section" ] || [ "$section" = "$group" ]; then
    printf '%s\n' "$group"
  else
    printf '%s: %s\n' "$group" "$section"
  fi
}

homes_render_check_rows_group_status() {
  local rows_file="$1" group="$2" row_group row_section name status detail result=ok found=false
  while IFS=$'\t' read -r row_group row_section name status detail; do
    [ -n "$row_group" ] || continue
    [ "$row_group" = "$group" ] || continue
    found=true
    if [ "$status" = fail ]; then
      printf 'fail\n'
      return 0
    fi
    [ "$status" = warn ] && result=warn
  done < "$rows_file"
  if [ "$found" != "true" ]; then
    printf 'warn\n'
  else
    printf '%s\n' "$result"
  fi
}

homes_render_check_rows_has_failure() {
  local rows_file="$1" row_group row_section name status detail
  while IFS=$'\t' read -r row_group row_section name status detail; do
    [ -n "$row_group" ] || continue
    [ "$status" = fail ] && return 0
  done < "$rows_file"
  return 1
}

homes_render_check_rows_warning_count() {
  local rows_file="$1" row_group row_section name status detail count=0
  while IFS=$'\t' read -r row_group row_section name status detail; do
    [ -n "$row_group" ] || continue
    [ "$status" = warn ] && count=$((count + 1))
  done < "$rows_file"
  printf '%s\n' "$count"
}

homes_render_check_rows_first_non_ok_detail() {
  local rows_file="$1" group="$2" row_group row_section name status detail
  while IFS=$'\t' read -r row_group row_section name status detail; do
    [ -n "$row_group" ] || continue
    [ "$row_group" = "$group" ] || continue
    [ "$status" = ok ] && continue
    if [ "$row_section" = "$group" ] || [ -z "$row_section" ]; then
      printf '%s: %s\n' "$name" "$detail"
    else
      printf '%s / %s: %s\n' "$row_section" "$name" "$detail"
    fi
    return 0
  done < "$rows_file"
  printf 'review details\n'
}

homes_render_check_rows_detail() {
  local rows_file="$1" group="$2" section="$3" label="$4" row_group row_section name status detail
  while IFS=$'\t' read -r row_group row_section name status detail; do
    [ "$row_group" = "$group" ] || continue
    [ "$row_section" = "$section" ] || continue
    [ "$name" = "$label" ] || continue
    printf '%s\n' "$detail"
    return 0
  done < "$rows_file"
  return 1
}

homes_render_check_rows_count_ok_prefixed() {
  local rows_file="$1" group="$2" prefix="$3" row_group row_section name status detail count=0
  while IFS=$'\t' read -r row_group row_section name status detail; do
    [ "$row_group" = "$group" ] || continue
    case "$name" in
      "$prefix"*) [ "$status" = ok ] && count=$((count + 1)) ;;
    esac
  done < "$rows_file"
  printf '%s\n' "$count"
}

homes_render_check_rows_group_sections() {
  local rows_file="$1" group="$2" row_group row_section name status detail last_section=""
  while IFS=$'\t' read -r row_group row_section name status detail; do
    [ -n "$row_group" ] || continue
    [ "$row_group" = "$group" ] || continue
    [ "$row_section" = "$last_section" ] && continue
    printf '%s\n' "$row_section"
    last_section="$row_section"
  done < "$rows_file"
}

homes_render_check_rows_section_table() {
  local rows_file="$1" group="$2" section="$3" color_mode="$4" row_group row_section name status detail
  homes_render_status_table_stream "Check" "$color_mode" < <(
    while IFS=$'\t' read -r row_group row_section name status detail; do
      [ "$row_group" = "$group" ] || continue
      [ "$row_section" = "$section" ] || continue
      printf '%s\t%s\t%s\n' "$name" "$status" "$detail"
    done < "$rows_file"
  )
}

homes_render_check_rows_print_failed_groups() {
  local rows_file="$1" color_mode="$2" group section status title
  shift 2
  for group in "$@"; do
    status=$(homes_render_check_rows_group_status "$rows_file" "$group")
    [ "$status" = ok ] && continue
    while IFS= read -r section; do
      title=$(homes_render_check_rows_section_title "$group" "$section")
      printf '\n'
      homes_render_heading "$title" "$color_mode"
      homes_render_check_rows_section_table "$rows_file" "$group" "$section" "$color_mode"
    done < <(homes_render_check_rows_group_sections "$rows_file" "$group")
  done
}

homes_render_check_rows_json_sections() {
  local rows_file="$1" row_group row_section name status detail key current_key="" first_section=true first_check=true title
  while IFS=$'\t' read -r row_group row_section name status detail; do
    [ -n "$row_group" ] || continue
    key="$row_group"$'\t'"$row_section"
    if [ "$key" != "$current_key" ]; then
      if [ -n "$current_key" ]; then
        printf ']}'
      fi
      if [ "$first_section" = "true" ]; then first_section=false; else printf ','; fi
      title=$(homes_render_check_rows_section_title "$row_group" "$row_section")
      printf '{"name":'; homes_json_string "$title"
      printf ',"checks":['
      current_key="$key"
      first_check=true
    fi

    if [ "$first_check" = "true" ]; then first_check=false; else printf ','; fi
    printf '{"name":'; homes_json_string "$name"
    printf ',"status":'; homes_json_string "$status"
    printf ',"detail":'; homes_json_string "$detail"
    printf '}'
  done < "$rows_file"
  if [ -n "$current_key" ]; then
    printf ']}'
  fi
}
