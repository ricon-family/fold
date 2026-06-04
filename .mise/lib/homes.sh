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
NOTES_BIN="${NOTES:-notes}"
export GIT_BIN GPG_BIN NOTES_BIN

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
  local home_path="$1" status

  if ! status=$("$GIT_BIN" -C "$home_path" status --porcelain); then
    echo "ERROR: could not inspect worktree: $home_path" >&2
    exit 1
  fi
  if [ -n "$status" ]; then
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

  if ! notes_changes=$(cd "$home_path" && "$NOTES_BIN" changes --summary 2>&1); then
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

homes_first_obfuscated_note() {
  local home_path="$1" first

  if ! first=$("$GIT_BIN" -C "$home_path" ls-tree -r --name-only HEAD notes 2>/dev/null \
      | awk '$0 != "notes/.manifest" { print; exit }'); then
    first=""
  fi

  if [ -z "$first" ]; then
    echo "ERROR: no obfuscated notes found in HEAD" >&2
    exit 1
  fi

  printf '%s\n' "$first"
}

homes_assert_publishable_tree() {
  local home_path="$1" first_note

  homes_require_git_repo "$home_path"
  homes_require_head "$home_path"
  homes_require_clean_worktree "$home_path"
  homes_require_no_pending_note_changes "$home_path"
  homes_fail_on_tracked_readable_notes "$home_path"

  homes_assert_gitcrypt_blob "$home_path" 'HEAD:notes/.manifest'
  homes_assert_gitcrypt_blob "$home_path" 'HEAD:.modules/manifest'
  first_note=$(homes_first_obfuscated_note "$home_path")
  homes_assert_gitcrypt_blob "$home_path" "HEAD:$first_note"
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

homes_require_remote_reachable() {
  local remote_url="$1"
  if ! "$GIT_BIN" ls-remote "$remote_url" >/dev/null 2>&1; then
    echo "ERROR: remote is not reachable: $remote_url" >&2
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
