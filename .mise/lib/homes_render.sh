#!/usr/bin/env bash
# Small TSV-backed render helpers for homes:* tasks.
# Source after homes.sh so homes_json_string is available.
set -euo pipefail

homes_render_record_row() {
  local file="$1" label="$2" status="$3" detail="$4"
  printf '%s\t%s\t%s\n' "$label" "$status" "$detail" >> "$file"
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

homes_render_table() {
  local file="$1" color_mode="$2" name status detail badge
  if command -v gum >/dev/null 2>&1; then
    {
      printf 'Check\tStatus\tDetail\n'
      while IFS=$'\t' read -r name status detail; do
        [ -n "$name" ] || continue
        badge=$(homes_render_status_badge "$status" "$color_mode")
        printf '%s\t%s\t%s\n' "$name" "$badge" "$detail"
      done < "$file"
    } | gum table --print --separator $'\t' --border rounded
  else
    printf 'Check\tStatus\tDetail\n'
    while IFS=$'\t' read -r name status detail; do
      [ -n "$name" ] || continue
      badge=$(homes_render_status_badge "$status" "$color_mode")
      printf '%s\t%s\t%s\n' "$name" "$badge" "$detail"
    done < "$file"
  fi
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
