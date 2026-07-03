#!/usr/bin/env bash
# Target parsing and default home target discovery for github:ci:* tasks.

github_ci_parse_repo_target() {
  local target="$1" repo agent

  if [[ "$target" == *:* ]]; then
    repo="${target%%:*}"
    agent="${target#*:}"
    [ -n "$agent" ] || github_ci_die "repo target agent cannot be empty: $target"
  else
    github_ci_die "repo target must include :agent for CI secret checks: $target"
  fi

  validate_repo "$repo"
  validate_agent "$agent"
  printf '%s\t%s\n' "$repo" "$agent"
}

github_ci_default_targets() {
  local json
  if ! json=$(cd "${MISE_CONFIG_ROOT:?MISE_CONFIG_ROOT not set}" && mise run -q agent:list --ci --json); then
    github_ci_die "could not list CI agents"
  fi

  if ! printf '%s' "$json" | "$GITHUB_CI_JQ_BIN" -e 'type == "array"' >/dev/null; then
    github_ci_die "agent:list --json did not return an array"
  fi

  if printf '%s' "$json" | "$GITHUB_CI_JQ_BIN" -e '.[] | select((.github_login // "") == "")' >/dev/null; then
    github_ci_die "all CI agents need github_login metadata for home repo targeting"
  fi

  printf '%s' "$json" | "$GITHUB_CI_JQ_BIN" -r '.[] | "\(.github_login)/home:\(.name)"'
}

github_ci_targets_file() {
  local repo_arg="$1" out="$2" target parsed had_explicit=false

  : > "$out"
  while IFS= read -r target; do
    [ -n "$target" ] || continue
    had_explicit=true
    parsed=$(github_ci_parse_repo_target "$target")
    printf '%s\n' "$parsed" >> "$out"
  done < <(parse_values "$repo_arg")

  if [ "$had_explicit" = "false" ]; then
    while IFS= read -r target; do
      [ -n "$target" ] || continue
      parsed=$(github_ci_parse_repo_target "$target")
      printf '%s\n' "$parsed" >> "$out"
    done < <(github_ci_default_targets)
  fi

  if [ ! -s "$out" ]; then
    github_ci_die "no home repo targets found"
  fi
}
