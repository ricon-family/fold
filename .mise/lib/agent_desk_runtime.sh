#!/usr/bin/env bash
set -euo pipefail

agent_desk_runtime_error() {
  printf 'ERROR: target identity verification failed: %s\n' "$1" >&2
  exit 1
}

agent_desk_runtime_require() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    agent_desk_runtime_error "missing runtime input: $name"
  fi
}

agent_desk_runtime_select_home() {
  local actual_home home_root

  # Keep persona values and their ownership record together for activation.
  unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR
  unset AGENT_HOME AGENT_IDENTITY CHAT_IDENTITY EMAILS_CONFIG HIMALAYA_CONFIG
  unset GITHUB_TOKEN GH_CONFIG_DIR __MISE_DIFF

  cd "$AGENT_DESK_HOME"
  actual_home=$(pwd -P)
  [ "$actual_home" = "$AGENT_DESK_HOME" ] || \
    agent_desk_runtime_error "working directory does not match the selected home"
  home_root=$(git rev-parse --show-toplevel) || \
    agent_desk_runtime_error "selected home is not a Git worktree"
  [ "$home_root" = "$actual_home" ] || \
    agent_desk_runtime_error "selected home must be the Git worktree root"
}

agent_desk_runtime_signing_keys_match() {
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

agent_desk_runtime_activate_persona() {
  local identity_shell

  identity_shell=$(cd "$AGENT_DESK_IDENTITY_SOURCE" && shimmer as "$AGENT_DESK_AGENT") || return $?
  eval "$identity_shell"
  unset identity_shell

  [ -z "${AGENT_HOME+x}" ] || \
    agent_desk_runtime_error "persona activation must not assign AGENT_HOME"
}

agent_desk_runtime_verify_git_and_github() {
  local actual_github actual_name actual_email actual_signing_key

  [ "${GIT_AUTHOR_NAME:-}" = "$AGENT_DESK_EXPECTED_NAME" ] || \
    agent_desk_runtime_error "Git author name does not match the prepared target home"
  [ "${GIT_AUTHOR_EMAIL:-}" = "$AGENT_DESK_EXPECTED_EMAIL" ] || \
    agent_desk_runtime_error "Git author email is not $AGENT_DESK_EXPECTED_EMAIL"
  [ "${GIT_COMMITTER_NAME:-}" = "$AGENT_DESK_EXPECTED_NAME" ] || \
    agent_desk_runtime_error "Git committer name does not match the prepared target home"
  [ "${GIT_COMMITTER_EMAIL:-}" = "$AGENT_DESK_EXPECTED_EMAIL" ] || \
    agent_desk_runtime_error "Git committer email is not $AGENT_DESK_EXPECTED_EMAIL"

  actual_name=$(git -C "$AGENT_DESK_HOME" config --get user.name || true)
  actual_email=$(git -C "$AGENT_DESK_HOME" config --get user.email || true)
  actual_signing_key=$(git -C "$AGENT_DESK_HOME" config --get user.signingkey || true)
  [ "$actual_name" = "$AGENT_DESK_EXPECTED_NAME" ] || \
    agent_desk_runtime_error "Git config user.name does not match the prepared target home"
  [ "$actual_email" = "$AGENT_DESK_EXPECTED_EMAIL" ] || \
    agent_desk_runtime_error "Git config user.email is not $AGENT_DESK_EXPECTED_EMAIL"
  agent_desk_runtime_signing_keys_match \
    "$AGENT_DESK_EXPECTED_SIGNING_KEY" "$actual_signing_key" || \
    agent_desk_runtime_error "Git signing key does not match the prepared target home"
  [ "$(git -C "$AGENT_DESK_HOME" config --bool commit.gpgsign || true)" = true ] || \
    agent_desk_runtime_error "Git commit signing is not enabled"

  command -v "$AGENT_DESK_GH_BIN" >/dev/null 2>&1 || \
    agent_desk_runtime_error "GitHub CLI is unavailable: $AGENT_DESK_GH_BIN"
  if ! actual_github=$("$AGENT_DESK_GH_BIN" api user --jq .login); then
    agent_desk_runtime_error "GitHub authentication check failed"
  fi
  [ "$actual_github" = "$AGENT_DESK_EXPECTED_GITHUB_LOGIN" ] || \
    agent_desk_runtime_error \
      "GitHub login is $actual_github, expected $AGENT_DESK_EXPECTED_GITHUB_LOGIN"
}

agent_desk_runtime_bind_home() {
  unset HIMALAYA_CONFIG __MISE_DIFF
  export EMAILS_CONFIG="$AGENT_DESK_HOME/.emails/himalaya.toml"
  export AGENT_HOME="$AGENT_DESK_HOME"
  export AGENT_IDENTITY="$AGENT_DESK_AGENT"
  export CHAT_IDENTITY="$AGENT_DESK_AGENT"
}

for required_input in \
  AGENT_DESK_MODE \
  AGENT_DESK_AGENT \
  AGENT_DESK_HOME \
  AGENT_DESK_IDENTITY_SOURCE \
  AGENT_DESK_PACKET \
  AGENT_DESK_MODEL \
  AGENT_DESK_TITLE \
  AGENT_DESK_EXPECTED_NAME \
  AGENT_DESK_EXPECTED_EMAIL \
  AGENT_DESK_EXPECTED_SIGNING_KEY \
  AGENT_DESK_EXPECTED_GITHUB_LOGIN \
  AGENT_DESK_GH_BIN; do
  agent_desk_runtime_require "$required_input"
done
unset required_input

case "$AGENT_DESK_MODE" in
  fresh) ;;
  resume)
    agent_desk_runtime_require AGENT_DESK_SESSION
    agent_desk_runtime_require AGENT_DESK_MESSAGE
    agent_desk_runtime_require AGENT_DESK_SESSIONS_BIN
    ;;
  *) agent_desk_runtime_error "unknown wake mode: $AGENT_DESK_MODE" ;;
esac

agent_desk_runtime_select_home
agent_desk_runtime_activate_persona
agent_desk_runtime_verify_git_and_github
agent_desk_runtime_bind_home

case "$AGENT_DESK_MODE" in
  fresh)
    packet=$(cat "$AGENT_DESK_PACKET")
    exec shimmer agent --model "$AGENT_DESK_MODEL" "[$AGENT_DESK_TITLE]
${packet}"
    ;;
  resume)
    exec "$AGENT_DESK_SESSIONS_BIN" wake "$AGENT_DESK_SESSION" \
      --model "$AGENT_DESK_MODEL" \
      --context-file "$AGENT_DESK_PACKET" \
      --message "[$AGENT_DESK_TITLE] $AGENT_DESK_MESSAGE"
    ;;
esac
