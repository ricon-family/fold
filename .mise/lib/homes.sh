#!/usr/bin/env bash
# Shared helpers for fold homes:* mise tasks.
#
# This is a lib, not a mise task. Self-locate via BASH_SOURCE rather than
# reading MISE_CONFIG_ROOT; agent sessions can inherit a stale MCR from the
# launcher repo. See fold/notes/mise-gotchas.md.
set -euo pipefail

HOMES_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.mise/lib/common.sh
source "$HOMES_LIB_DIR/common.sh"

GIT_BIN="${GIT:-git}"
GPG_BIN="${GPG:-gpg}"
MISE_BIN="${MISE_BIN:-${MISE:-mise}}"
NOTES_BIN="${NOTES:-notes}"
MODULES_BIN="${MODULES:-modules}"
export GIT_BIN GPG_BIN MISE_BIN NOTES_BIN MODULES_BIN

homes_agent_email() {
  printf '%s@ricon.family\n' "$1"
}

homes_default_home() {
  local agent="$1"
  printf '%s/agents/%s/home\n' "$HOME" "$agent"
}

homes_resolve_home() {
  local agent="$1" home_path="$2"
  if [ -n "$home_path" ]; then
    printf '%s\n' "$home_path"
  else
    homes_default_home "$agent"
  fi
}

homes_default_agents_root() {
  printf '%s/agents\n' "$HOME"
}

homes_resolve_agents_root() {
  local agents_root="$1"
  if [ -n "$agents_root" ]; then
    printf '%s\n' "$agents_root"
  else
    homes_default_agents_root
  fi
}

homes_agent_dir() {
  local agent="$1" agents_root="$2"
  printf '%s/%s\n' "$agents_root" "$agent"
}

homes_agent_dir_for_home() {
  local home_path="$1"
  dirname "$home_path"
}

homes_agent_gitconfig_path_for_dir() {
  local agent_dir="$1"
  printf '%s/.gitconfig\n' "$agent_dir"
}

homes_agent_gitconfig_path() {
  local agent="$1" agents_root="$2"
  homes_agent_gitconfig_path_for_dir "$(homes_agent_dir "$agent" "$agents_root")"
}

homes_agent_include_key_for_dir() {
  local agent="$1" agent_dir="$2"
  if [ "$agent_dir" = "$HOME/agents/$agent" ]; then
    printf 'includeIf.gitdir:~/agents/%s/.path\n' "$agent"
    return 0
  fi
  printf 'includeIf.gitdir:%s/.path\n' "$agent_dir"
}

homes_agent_include_key() {
  local agent="$1" agents_root="$2"
  homes_agent_include_key_for_dir "$agent" "$(homes_agent_dir "$agent" "$agents_root")"
}

homes_infer_agent_from_home() {
  local home_path="$1" base parent
  [ -n "$home_path" ] || return 1
  base=$(basename "$home_path")
  parent=$(basename "$(dirname "$home_path")")
  if [ "$base" = "home" ] && [ -n "$parent" ]; then
    printf '%s\n' "$parent"
    return 0
  fi
  return 1
}

homes_strip_wrapping_quotes() {
  local value="$1"
  if [[ "$value" == \"*\" ]]; then
    value="${value#\"}"
    value="${value%\"}"
  fi
  printf '%s\n' "$value"
}

homes_gpg_import_key_data() (
  local key_data="$1" tmp
  shift

  tmp=$(mktemp) || return 1
  trap 'rm -f "$tmp"' EXIT HUP INT TERM
  printf '%s' "$key_data" > "$tmp" || return 1
  "$GPG_BIN" --batch --import "$@" "$tmp"
)

homes_validate_gpg_key_data() {
  local key_data="$1"

  if [ -z "$key_data" ]; then
    echo "ERROR: GPG key is empty" >&2
    return 1
  fi
  if [[ "$key_data" == \"* ]]; then
    echo "ERROR: GPG key starts with a double quote — likely corrupted" >&2
    return 1
  fi
  if ! printf '%s' "$key_data" | head -1 | grep -q '^-----BEGIN PGP'; then
    echo "ERROR: GPG key does not start with a PGP armor header" >&2
    return 1
  fi

  if ! homes_gpg_import_key_data "$key_data" --dry-run >/dev/null 2>&1; then
    echo "ERROR: GPG cannot parse key" >&2
    return 1
  fi
}

homes_json_string() {
  local value="$1"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '"%s"' "$value"
}

homes_timeout_command() {
  command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null
}

homes_git_is_repo() {
  "$GIT_BIN" -C "$1" rev-parse --git-dir >/dev/null 2>&1
}

homes_git_head_label() {
  local repo="$1" head branch
  head=$("$GIT_BIN" -C "$repo" rev-parse --short HEAD 2>/dev/null) || return 1
  branch=$("$GIT_BIN" -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  [ -n "$branch" ] || branch="detached"
  [ "$branch" = "HEAD" ] && branch="detached"
  printf '%s @ %s\n' "$branch" "$head"
}

homes_git_worktree_state() {
  local repo="$1" status
  if ! status=$("$GIT_BIN" -C "$repo" status --porcelain 2>/dev/null); then
    printf 'unknown\n'
    return 1
  fi
  if [ -z "$status" ]; then
    printf 'clean\n'
  else
    printf 'dirty\n'
  fi
}

homes_git_origin_redacted() {
  local repo="$1" origin
  origin=$("$GIT_BIN" -C "$repo" remote get-url origin 2>/dev/null) || return 1
  homes_redact_url "$origin"
}

homes_github_remote_repo() {
  local remote_url="$1" path owner repo

  remote_url=$(homes_strip_wrapping_quotes "$remote_url")
  remote_url=${remote_url%/}

  case "$remote_url" in
    https://github.com/*)
      path=${remote_url#https://github.com/}
      ;;
    git@github.com:*)
      path=${remote_url#git@github.com:}
      ;;
    ssh://git@github.com/*)
      path=${remote_url#ssh://git@github.com/}
      ;;
    *)
      return 1
      ;;
  esac

  path=${path%.git}
  path=${path%/}
  owner=${path%%/*}
  repo=${path#*/}

  if [ -z "$owner" ] || [ -z "$repo" ] || [ "$owner" = "$path" ] || [[ "$repo" == */* ]]; then
    return 1
  fi

  printf '%s/%s\n' "$(lower "$owner")" "$(lower "$repo")"
}

homes_github_remote_matches_repo() {
  local remote_url="$1" expected_owner="$2" expected_repo="$3" actual expected

  actual=$(homes_github_remote_repo "$remote_url") || return 1
  expected="$(lower "$expected_owner")/$(lower "$expected_repo")"
  [ "$actual" = "$expected" ]
}

homes_manifest_state() {
  local manifest="$1"
  if [ ! -f "$manifest" ]; then
    printf 'missing\n'
  elif homes_file_is_gitcrypt_blob "$manifest"; then
    printf 'locked\n'
  else
    printf 'readable\n'
  fi
}

homes_notes_changes_summary() {
  local home_path="$1"
  (cd "$home_path" && "$NOTES_BIN" changes --summary)
}

homes_require_git_repo() {
  local home_path="$1"

  if [ ! -e "$home_path" ]; then
    echo "ERROR: home path does not exist: $home_path" >&2
    exit 1
  fi
  if [ ! -d "$home_path" ]; then
    echo "ERROR: home path is not a directory: $home_path" >&2
    exit 1
  fi
  if ! "$GIT_BIN" -C "$home_path" rev-parse --git-dir >/dev/null 2>&1; then
    echo "ERROR: home path is not a git repository: $home_path" >&2
    exit 1
  fi
}

homes_require_clean_worktree() {
  local home_path="$1" state

  if ! state=$(homes_git_worktree_state "$home_path"); then
    echo "ERROR: could not inspect worktree: $home_path" >&2
    exit 1
  fi
  if [ "$state" = "dirty" ]; then
    echo "ERROR: home worktree is dirty; commit/stash before continuing: $home_path" >&2
    "$GIT_BIN" -C "$home_path" status --short >&2
    exit 1
  fi
}

homes_require_head() {
  local home_path="$1"
  if ! "$GIT_BIN" -C "$home_path" rev-parse --verify HEAD >/dev/null 2>&1; then
    echo "ERROR: home repo has no commits: $home_path" >&2
    exit 1
  fi
}

homes_tracked_readable_notes() {
  local home_path="$1" tracked
  if ! tracked=$("$GIT_BIN" -C "$home_path" ls-files 'notes/*.md' 2>/dev/null); then
    tracked=""
  fi
  printf '%s\n' "$tracked"
}

homes_fail_on_tracked_readable_notes() {
  local home_path="$1" tracked
  tracked=$(homes_tracked_readable_notes "$home_path")
  if [ -n "$tracked" ]; then
    echo "ERROR: readable note filenames are tracked; obfuscate before publishing" >&2
    printf '%s\n' "$tracked" | sed 's/^/  /' >&2
    exit 1
  fi
}

homes_require_no_pending_note_changes() {
  local home_path="$1" notes_changes

  [ -f "$home_path/notes/.manifest" ] || return 0

  if ! command -v "$NOTES_BIN" >/dev/null 2>&1; then
    echo "ERROR: notes/.manifest exists but notes tool is unavailable" >&2
    exit 1
  fi

  if ! notes_changes=$(homes_notes_changes_summary "$home_path" 2>&1); then
    echo "ERROR: could not inspect notes workflow state before publishing" >&2
    printf '%s\n' "$notes_changes" >&2
    exit 1
  fi

  if [ "$notes_changes" != "No changes." ]; then
    echo "ERROR: note changes remain; resolve notes workflow before publishing" >&2
    printf '%s\n' "$notes_changes" | sed 's/^/  /' >&2
    exit 1
  fi
}

homes_blob_hex10() {
  local repo="$1" refpath="$2" tmp hex
  tmp=$(mktemp)
  "$GIT_BIN" -C "$repo" cat-file -p "$refpath" > "$tmp"
  hex=$(LC_ALL=C od -An -tx1 -N10 "$tmp" | tr -d ' \n')
  rm -f "$tmp"
  printf '%s\n' "$hex"
}

homes_file_hex10() {
  local path="$1" tmp hex
  tmp=$(mktemp)
  LC_ALL=C od -An -tx1 -N10 "$path" > "$tmp"
  hex=$(tr -d ' \n' < "$tmp")
  rm -f "$tmp"
  printf '%s\n' "$hex"
}

homes_file_is_gitcrypt_blob() {
  local path="$1"
  [ -f "$path" ] || return 1
  [ "$(homes_file_hex10 "$path")" = "00474954435259505400" ]
}

homes_assert_gitcrypt_blob() {
  local repo="$1" refpath="$2" hex

  if ! "$GIT_BIN" -C "$repo" cat-file -e "$refpath" 2>/dev/null; then
    echo "ERROR: missing required encrypted blob: $refpath" >&2
    exit 1
  fi

  hex=$(homes_blob_hex10 "$repo" "$refpath")
  if [ "$hex" != "00474954435259505400" ]; then
    echo "ERROR: $refpath is not a git-crypt blob (hex=$hex)" >&2
    exit 1
  fi

  printf 'encrypted: %s\n' "$refpath"
}

homes_assert_encrypted_note_blobs() {
  local repo="$1" path count
  count=0

  while IFS= read -r path; do
    [ -n "$path" ] || continue
    [ "$path" = "notes/.manifest" ] && continue
    count=$((count + 1))
    homes_assert_gitcrypt_blob "$repo" "HEAD:$path"
  done < <("$GIT_BIN" -C "$repo" ls-tree -r --name-only HEAD notes 2>/dev/null)

  if [ "$count" -eq 0 ]; then
    echo "ERROR: no obfuscated notes found in HEAD" >&2
    exit 1
  fi
}

homes_assert_publishable_tree() {
  local home_path="$1"

  homes_require_git_repo "$home_path"
  homes_require_head "$home_path"
  homes_require_clean_worktree "$home_path"
  homes_require_no_pending_note_changes "$home_path"
  homes_fail_on_tracked_readable_notes "$home_path"

  homes_assert_gitcrypt_blob "$home_path" 'HEAD:notes/.manifest'
  homes_assert_gitcrypt_blob "$home_path" 'HEAD:.modules/manifest'
  homes_assert_encrypted_note_blobs "$home_path"
}

homes_resolve_remote_url() {
  local repo="$1" remote_url="$2"

  if [ -n "$remote_url" ]; then
    printf '%s\n' "$remote_url"
    return 0
  fi

  if [ -z "$repo" ]; then
    echo "ERROR: provide --remote-url or --repo" >&2
    exit 1
  fi

  validate_repo "$repo"
  printf 'https://github.com/%s.git\n' "$repo"
}

homes_redact_url() {
  printf '%s' "$1" | redact_github_tokens
}

homes_git_redacted() {
  "$GIT_BIN" "$@" 2> >(redact_github_tokens >&2)
}

homes_require_remote_reachable() {
  local remote_url="$1"
  if ! homes_git_redacted ls-remote "$remote_url" >/dev/null; then
    echo "ERROR: remote is not reachable: $(homes_redact_url "$remote_url")" >&2
    exit 1
  fi
}

homes_remote_branch_exists() {
  local remote_url="$1" branch="$2"
  "$GIT_BIN" ls-remote --exit-code "$remote_url" "refs/heads/$branch" >/dev/null 2>&1
}

homes_agent_fingerprint() {
  local agent="$1" fingerprint
  validate_agent "$agent"

  if ! fingerprint=$("$SECRETS_BIN" get "$agent/gpg-fingerprint" 2>/dev/null); then
    echo "ERROR: could not read $agent/gpg-fingerprint" >&2
    exit 1
  fi
  if [ -z "$fingerprint" ]; then
    echo "ERROR: $agent/gpg-fingerprint is empty" >&2
    exit 1
  fi
  printf '%s\n' "$fingerprint"
}

homes_agent_git() {
  local agent="$1" sign="$2" email fingerprint
  shift 2

  validate_agent "$agent"
  email=$(homes_agent_email "$agent")

  if [ "$sign" = "true" ]; then
    fingerprint=$(homes_agent_fingerprint "$agent")
    env \
      -u GIT_CONFIG_COUNT \
      GIT_AUTHOR_NAME="$agent" \
      GIT_AUTHOR_EMAIL="$email" \
      GIT_COMMITTER_NAME="$agent" \
      GIT_COMMITTER_EMAIL="$email" \
      "$GIT_BIN" \
        -c user.name="$agent" \
        -c user.email="$email" \
        -c user.signingkey="$fingerprint" \
        -c commit.gpgsign=true \
        -c tag.gpgsign=true \
        "$@"
  else
    env \
      -u GIT_CONFIG_COUNT \
      GIT_AUTHOR_NAME="$agent" \
      GIT_AUTHOR_EMAIL="$email" \
      GIT_COMMITTER_NAME="$agent" \
      GIT_COMMITTER_EMAIL="$email" \
      "$GIT_BIN" \
        -c user.name="$agent" \
        -c user.email="$email" \
        -c commit.gpgsign=false \
        -c tag.gpgsign=false \
        "$@"
  fi
}
