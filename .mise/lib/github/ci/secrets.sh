#!/usr/bin/env bash
# Secret naming, source mapping, and GitHub Actions secret primitives.

github_ci_agent_secret_prefix() {
  local agent="$1"
  validate_agent "$agent"
  printf '%s' "$agent" | tr '[:lower:]' '[:upper:]' | sed 's/[^A-Z0-9]/_/g'
}

github_ci_required_agent_secrets() {
  local agent="$1" prefix
  prefix=$(github_ci_agent_secret_prefix "$agent")
  printf '%s_GITHUB_PAT\n' "$prefix"
  printf '%s_GPG_PRIVATE_KEY\n' "$prefix"
  printf '%s_EMAIL_PASSWORD\n' "$prefix"
}

github_ci_required_agent_secret_sources() {
  local agent="$1" prefix
  validate_agent "$agent"
  prefix=$(github_ci_agent_secret_prefix "$agent")
  printf '%s_GITHUB_PAT\t%s/github-pat\n' "$prefix" "$agent"
  printf '%s_GPG_PRIVATE_KEY\t%s/gpg-private-key\n' "$prefix" "$agent"
  printf '%s_EMAIL_PASSWORD\t%s/email-password\n' "$prefix" "$agent"
}

github_ci_agent_pat_secret_source() {
  local agent="$1" prefix
  validate_agent "$agent"
  prefix=$(github_ci_agent_secret_prefix "$agent")
  printf '%s_GITHUB_PAT\t%s/github-pat\n' "$prefix" "$agent"
}

github_ci_required_secret_names() {
  local scope="$1" agent="$2"

  case "$scope" in
    agent-home)
      github_ci_required_agent_secrets "$agent"
      printf 'PI_AUTH_JSON\n'
      ;;
    agent-secrets)
      github_ci_required_agent_secrets "$agent"
      ;;
    pi-auth)
      validate_agent "$agent"
      printf 'PI_AUTH_JSON\n'
      ;;
    *)
      github_ci_die "unknown CI secret status scope: $scope"
      ;;
  esac
}

github_ci_error_secret_name() {
  local scope="$1"
  case "$scope" in
    agent-home|agent-secrets) printf '-' ;;
    pi-auth) printf 'PI_AUTH_JSON' ;;
    *) github_ci_die "unknown CI secret status scope: $scope" ;;
  esac
}

github_ci_get_agent_github_pat() {
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

github_ci_secret_names_file() {
  local repo="$1" agent="$2" out="$3"
  validate_agent "$agent"

  if ! "$GH_BIN" secret list --repo "$repo" --json name --jq '.[].name' > "$out"; then
    return 1
  fi
}

github_ci_secret_present() {
  local names_file="$1" secret="$2"
  grep -Fxq "$secret" "$names_file"
}

github_ci_sanitize_detail() {
  redact_github_tokens | tr '\n\t' '  ' | sed 's/[[:space:]]\{1,\}/ /g; s/^ //; s/ $//' | cut -c 1-160
}

github_ci_normalize_secret_value() {
  local source_key="$1" value="$2"

  case "$source_key" in
    */gpg-private-key)
      if [[ "$value" == \"* ]]; then
        value="${value#\"}"
        value="${value%\"}"
      fi
      ;;
  esac

  printf '%s' "$value"
}

github_ci_set_github_secret_value() {
  local repo="$1" agent="$2" secret="$3" value="$4"
  validate_agent "$agent"

  if ! printf '%s' "$value" | "$GH_BIN" secret set "$secret" --repo "$repo" >/dev/null; then
    unset value
    return 1
  fi

  unset value
}

github_ci_set_github_secret_file() {
  local repo="$1" agent="$2" secret="$3" file="$4"
  validate_agent "$agent"

  if ! "$GH_BIN" secret set "$secret" --repo "$repo" < "$file" >/dev/null; then
    return 1
  fi
}
