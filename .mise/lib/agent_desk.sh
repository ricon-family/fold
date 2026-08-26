#!/usr/bin/env bash
# Shared helpers for agent desk diagnostic mise tasks.
#
# This is a lib, not a mise task. Keep helpers read-only unless the calling
# task is explicitly mutating.

# shellcheck disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

AGENT_DESK_SHELL_BIN="${SHELL_BIN:-shell}"

agent_desk_validate_name() {
  local kind="$1" value="$2"
  if [[ ! "$value" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "ERROR: invalid $kind: $value" >&2
    echo "$kind may contain letters, numbers, dot, underscore, and hyphen." >&2
    exit 1
  fi
}

agent_desk_abs_path() {
  local path="$1"
  if [ -z "$path" ]; then
    return 1
  fi
  if [ ! -e "$path" ]; then
    echo "ERROR: path does not exist: $path" >&2
    exit 1
  fi
  (cd "$path" && pwd -P)
}

agent_desk_abs_file() {
  local path="$1" dir base
  if [ -z "$path" ]; then
    return 1
  fi
  if [ ! -f "$path" ]; then
    echo "ERROR: file does not exist: $path" >&2
    exit 1
  fi
  dir=$(dirname "$path")
  base=$(basename "$path")
  printf '%s/%s\n' "$(cd "$dir" && pwd -P)" "$base"
}

agent_desk_find_from_cwd() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/.desk/registry.json" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

agent_desk_resolve_desk() {
  local explicit="$1"
  if [ -n "$explicit" ]; then
    agent_desk_abs_path "$explicit"
    return 0
  fi
  if [ -n "${DESK_ROOT:-}" ] && [ -d "$DESK_ROOT" ]; then
    agent_desk_abs_path "$DESK_ROOT"
    return 0
  fi
  agent_desk_find_from_cwd || true
}

agent_desk_resolve_home() {
  local explicit="$1" desk="$2"
  if [ -n "$explicit" ]; then
    agent_desk_abs_path "$explicit"
    return 0
  fi
  if [ -n "$desk" ] && [ -d "$desk/home" ]; then
    agent_desk_abs_path "$desk/home"
    return 0
  fi
  if git -C "$PWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$PWD" rev-parse --show-toplevel
    return 0
  fi
  return 1
}

agent_desk_shell_status() {
  local shell_name="$1"
  "$AGENT_DESK_SHELL_BIN" status "$shell_name"
}

agent_desk_shell_history_tail() {
  local shell_name="$1" lines="$2"
  "$AGENT_DESK_SHELL_BIN" history "$shell_name" | tail -n "$lines"
}

agent_desk_git_status() {
  local label="$1" repo="$2" recent="$3"
  printf '\n== %s ==\n' "$label"
  printf 'path: %s\n' "$repo"
  if [ ! -d "$repo/.git" ] && ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
    printf 'not a git repo\n'
    return 0
  fi
  git -C "$repo" status --short --branch
  if [ "$recent" -gt 0 ] 2>/dev/null; then
    git -C "$repo" log --oneline --decorate -n "$recent"
  fi
}

agent_desk_list_default_repos() {
  local desk="$1"
  [ -n "$desk" ] || return 0
  [ -d "$desk" ] || return 0

  find "$desk" -maxdepth 2 -name .git -type d -print | sort | while IFS= read -r git_dir; do
    repo=${git_dir%/.git}
    label=${repo##*/}
    printf '%s=%s\n' "$label" "$repo"
  done
}

agent_desk_parse_repo_spec() {
  local spec="$1"
  if [[ "$spec" != *=* ]]; then
    echo "ERROR: repo specs must be label=path: $spec" >&2
    exit 1
  fi
  printf '%s\t%s\n' "${spec%%=*}" "${spec#*=}"
}

agent_desk_single_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\''/g")"
}

agent_desk_clean_git_config_get() {
  local repo="$1" key="$2"
  env \
    -u GIT_CONFIG_COUNT \
    -u GIT_CONFIG_PARAMETERS \
    -u GIT_CONFIG_GLOBAL \
    -u GIT_CONFIG_SYSTEM \
    -u GIT_CONFIG_NOSYSTEM \
    git -C "$repo" config --get "$key"
}

agent_desk_github_login() {
  local agent="$1" jq_bin="$2" records login

  if ! records=$(mise run -q agent:list --json); then
    echo "ERROR: could not resolve agent metadata for $agent" >&2
    return 1
  fi
  login=$(
    printf '%s\n' "$records" |
      "$jq_bin" -r --arg agent "$agent" \
        '[.[] | select(.name == $agent) | .github_login] | if length == 1 then .[0] else "" end'
  )
  if [ -z "$login" ]; then
    echo "ERROR: agent metadata has no unique GitHub login for $agent" >&2
    return 1
  fi
  printf '%s\n' "$login"
}

agent_desk_render_identity_boundary() {
  cat <<'IDENTITY_BOUNDARY'
agent_desk_scrub_inherited_identity() {
  local variable

  while IFS= read -r variable; do
    [ -n "$variable" ] || continue
    unset "$variable"
  done < <(compgen -A variable GIT_CONFIG_ || true)

  unset \
    AGENT_HOME AGENT_IDENTITY CHAT_IDENTITY \
    EMAILS_CONFIG HIMALAYA_CONFIG \
    GH_TOKEN GITHUB_TOKEN GH_CONFIG_DIR \
    GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL \
    GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL \
    __MISE_DIFF
}

agent_desk_identity_error() {
  printf 'ERROR: target identity verification failed: %s\n' "$1" >&2
  exit 1
}

agent_desk_signing_keys_match() {
  local expected actual

  expected=$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]' | sed 's/^0X//')
  actual=$(printf '%s' "$2" | tr '[:lower:]' '[:upper:]' | sed 's/^0X//')
  case "$expected:$actual" in
    *[!0-9A-F:]*|:*|*:) return 1 ;;
  esac
  [ "${#expected}" -ge 16 ] || return 1
  [ "${#actual}" -ge 16 ] || return 1
  [ "$expected" = "$actual" ] && return 0
  case "$expected" in *"$actual") return 0 ;; esac
  case "$actual" in *"$expected") return 0 ;; esac
  return 1
}

agent_desk_activate_target_identity() {
  local actual_home actual_github actual_name actual_email actual_signing_key
  local identity_shell

  agent_desk_scrub_inherited_identity
  identity_shell=$(cd "$IDENTITY_SOURCE" && shimmer as "$AGENT") || return $?
  eval "$identity_shell"
  unset identity_shell

  [ -n "${AGENT_HOME:-}" ] || \
    agent_desk_identity_error "shimmer did not set AGENT_HOME"
  actual_home=$(cd "$AGENT_HOME" && pwd -P)
  if [ "$actual_home" != "$HOME_PATH" ]; then
    printf 'ERROR: authenticated agent home does not match desk home\n' >&2
    printf '  authenticated home: %s\n' "$actual_home" >&2
    printf '  desk home:          %s\n' "$HOME_PATH" >&2
    exit 1
  fi

  [ "${GIT_AUTHOR_NAME:-}" = "$AGENT" ] || \
    agent_desk_identity_error "Git author name is not $AGENT"
  [ "${GIT_AUTHOR_EMAIL:-}" = "$EXPECTED_EMAIL" ] || \
    agent_desk_identity_error "Git author email is not $EXPECTED_EMAIL"
  [ "${GIT_COMMITTER_NAME:-}" = "$AGENT" ] || \
    agent_desk_identity_error "Git committer name is not $AGENT"
  [ "${GIT_COMMITTER_EMAIL:-}" = "$EXPECTED_EMAIL" ] || \
    agent_desk_identity_error "Git committer email is not $EXPECTED_EMAIL"

  actual_name=$(git -C "$HOME_PATH" config --get user.name || true)
  actual_email=$(git -C "$HOME_PATH" config --get user.email || true)
  actual_signing_key=$(git -C "$HOME_PATH" config --get user.signingkey || true)
  [ "$actual_name" = "$AGENT" ] || \
    agent_desk_identity_error "Git config user.name is not $AGENT"
  [ "$actual_email" = "$EXPECTED_EMAIL" ] || \
    agent_desk_identity_error "Git config user.email is not $EXPECTED_EMAIL"
  agent_desk_signing_keys_match "$EXPECTED_SIGNING_KEY" "$actual_signing_key" || \
    agent_desk_identity_error "Git signing key does not match the prepared target home"
  [ "$(git -C "$HOME_PATH" config --bool commit.gpgsign || true)" = true ] || \
    agent_desk_identity_error "Git commit signing is not enabled"

  command -v "$GH_BIN" >/dev/null 2>&1 || \
    agent_desk_identity_error "GitHub CLI is unavailable: $GH_BIN"
  if ! actual_github=$("$GH_BIN" api user --jq .login); then
    agent_desk_identity_error "GitHub authentication check failed"
  fi
  [ "$actual_github" = "$EXPECTED_GITHUB_LOGIN" ] || \
    agent_desk_identity_error \
      "GitHub login is $actual_github, expected $EXPECTED_GITHUB_LOGIN"

  unset HIMALAYA_CONFIG __MISE_DIFF
  export EMAILS_CONFIG="$actual_home/.emails/himalaya.toml"
  export AGENT_HOME="$actual_home"
  export AGENT_IDENTITY="$AGENT"
  export CHAT_IDENTITY="$AGENT"
}

agent_desk_activate_target_identity
IDENTITY_BOUNDARY
}
