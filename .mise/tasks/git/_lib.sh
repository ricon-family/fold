#!/usr/bin/env bash

CHECKS_FAILED=0
CHECKS_WARNED=0

info() {
  printf '  • %s\n' "$*"
}

ok() {
  printf '  ✓ %s\n' "$*"
}

warn() {
  CHECKS_WARNED=$((CHECKS_WARNED + 1))
  printf '  ⚠ %s\n' "$*"
}

fail() {
  CHECKS_FAILED=$((CHECKS_FAILED + 1))
  printf '  ✗ %s\n' "$*"
}

section() {
  printf '\n%s\n' "$1"
  printf '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n'
}

show_invocation_header() {
  local task_name="$1"

  printf '%s\n' "$task_name"
  if [ "${FOLD_GIT_SHIM:-}" = "1" ]; then
    info "called as: ${FOLD_GIT_SHIM_COMMAND:-git preflight}"
    info "git found a PATH executable named ${FOLD_GIT_SHIM_EXECUTABLE:-git-preflight}; this is a fold preflight task, not a Git hook"
    if [ -n "${FOLD_CALLER_PWD:-}" ]; then
      info "default target: caller cwd ($FOLD_CALLER_PWD)"
    fi
  fi
}

resolve_target_path() {
  local path="${1:-}"
  local caller_pwd="${FOLD_CALLER_PWD:-}"

  if [ -z "$path" ]; then
    if [ -n "$caller_pwd" ]; then
      path="$caller_pwd"
    else
      path="."
    fi
  fi

  case "$path" in
    /*) printf '%s\n' "$path" ;;
    *)
      if [ -n "$caller_pwd" ]; then
        printf '%s/%s\n' "$caller_pwd" "$path"
      else
        printf '%s\n' "$path"
      fi
      ;;
  esac
}

resolve_repo() {
  local path target
  path="$1"
  target=$(resolve_target_path "$path")

  if [ ! -e "$target" ]; then
    fail "path does not exist: $target"
    return 1
  fi
  if ! git -C "$target" rev-parse --show-toplevel >/dev/null 2>&1; then
    fail "not a git repository: $target"
    return 1
  fi
  git -C "$target" rev-parse --show-toplevel
}

detect_active_agent() {
  local candidate local_part

  candidate="${AGENT_NAME:-}"
  if [ -n "$candidate" ] && [ -d "$HOME/agents/$candidate/home" ]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  candidate="${GIT_AUTHOR_NAME:-}"
  if [ -n "$candidate" ] && [ -d "$HOME/agents/$candidate/home" ]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  if [ -n "${GIT_AUTHOR_EMAIL:-}" ]; then
    local_part=${GIT_AUTHOR_EMAIL%@*}
    if [ -n "$local_part" ] && [ -d "$HOME/agents/$local_part/home" ]; then
      printf '%s\n' "$local_part"
      return 0
    fi
  fi

  printf '%s\n' "${GIT_AUTHOR_NAME:-}"
}

expected_signing_key() {
  local agent="$1"
  local home_dir

  [ -n "$agent" ] || return 1
  home_dir="$HOME/agents/$agent/home"
  [ -d "$home_dir" ] || return 1
  git -C "$home_dir" config --get user.signingkey 2>/dev/null
}

show_repo_identity() {
  local repo="$1"
  local branch remote head
  branch=$(git -C "$repo" branch --show-current 2>/dev/null || true)
  remote=$(git -C "$repo" remote -v 2>/dev/null | awk 'NR == 1 {print $2}' || true)
  head=$(git -C "$repo" rev-parse --short HEAD 2>/dev/null || true)

  info "repo: $repo"
  info "branch: ${branch:-detached}"
  info "HEAD: ${head:-unknown}"
  info "remote: ${remote:-none}"
  if [ -n "${FOLD_CALLER_PWD:-}" ]; then
    info "caller cwd: $FOLD_CALLER_PWD"
  fi
}

show_git_identity() {
  local repo="$1"
  local cfg_name cfg_email cfg_key cfg_sign env_name env_email env_committer env_committer_email agent expected_key

  cfg_name=$(git -C "$repo" config --get user.name || true)
  cfg_email=$(git -C "$repo" config --get user.email || true)
  cfg_key=$(git -C "$repo" config --get user.signingkey || true)
  cfg_sign=$(git -C "$repo" config --get commit.gpgsign || true)
  env_name=${GIT_AUTHOR_NAME:-}
  env_email=${GIT_AUTHOR_EMAIL:-}
  env_committer=${GIT_COMMITTER_NAME:-}
  env_committer_email=${GIT_COMMITTER_EMAIL:-}
  agent=$(detect_active_agent)

  info "git config user: ${cfg_name:-unset} <${cfg_email:-unset}>"
  info "git config signing key: ${cfg_key:-unset}"
  info "commit.gpgsign: ${cfg_sign:-unset}"
  info "env author: ${env_name:-unset} <${env_email:-unset}>"
  info "env committer: ${env_committer:-unset} <${env_committer_email:-unset}>"
  info "active agent: ${agent:-unknown}"

  if [ -z "$env_name" ] || [ -z "$env_email" ]; then
    warn "GIT_AUTHOR_* is not set; commit may use repo/global identity"
  fi
  if [ -z "$env_committer" ] || [ -z "$env_committer_email" ]; then
    warn "GIT_COMMITTER_* is not set; commit may use repo/global identity"
  fi
  if [ "${cfg_sign:-}" != "true" ]; then
    warn "commit.gpgsign is not true; commits may be unsigned unless overridden"
  fi

  if expected_key=$(expected_signing_key "$agent"); then
    if [ -n "$expected_key" ]; then
      info "expected key for $agent: $expected_key"
      if [ -n "$cfg_key" ] && [ "$cfg_key" != "$expected_key" ]; then
        warn "repo/global signing key differs from active agent key; use transient -c user.signingkey=$expected_key"
      elif [ -z "$cfg_key" ]; then
        warn "no repo/global signing key found; signed commits/tags may fail"
      fi
    fi
  elif [ -n "$agent" ]; then
    warn "could not determine expected signing key for active agent '$agent'"
  fi
}

show_notes_state() {
  local repo="$1"
  if [ ! -f "$repo/notes/.manifest" ]; then
    info "notes: no notes/.manifest"
    return 0
  fi

  if ! command -v notes >/dev/null 2>&1; then
    warn "notes manifest present but notes command not found"
    return 0
  fi

  info "notes changes:"
  if (cd "$repo" && notes changes --summary) | sed 's/^/    /'; then
    :
  else
    warn "notes changes --summary failed"
  fi

  if git -C "$repo" status --short -- notes/.manifest | grep -q .; then
    warn "notes/.manifest is dirty in git status"
  else
    ok "notes/.manifest clean"
  fi
}

show_modules_state() {
  local repo="$1"
  if [ ! -f "$repo/.modules/manifest" ]; then
    info "modules: no .modules/manifest"
    return 0
  fi

  if git -C "$repo" status --short -- .modules/manifest | grep -q .; then
    warn ".modules/manifest is dirty in git status"
  else
    ok ".modules/manifest clean"
  fi

  if command -v modules >/dev/null 2>&1; then
    info "modules manifest present; run modules init/update intentionally when needed"
  else
    warn "modules manifest present but modules command not found"
  fi
}

show_tracked_dirty_state() {
  local repo="$1"
  git -C "$repo" status --short --branch
  if git -C "$repo" diff --quiet && git -C "$repo" diff --cached --quiet; then
    ok "working tree has no tracked dirty changes"
  else
    fail "tracked dirty changes present; commit/stash before publishing"
  fi
}

show_untracked_warning() {
  local repo="$1"
  local untracked
  untracked=$(git -C "$repo" ls-files --others --exclude-standard | sed -n '1,5p')
  if [ -n "$untracked" ]; then
    warn "untracked files present (first few):"
    printf '%s\n' "$untracked" | sed 's/^/    /'
  fi
}

show_commit_signatures() {
  local repo="$1"
  local range="$2"
  local limit="${3:-0}"
  local commit_count sig_mismatch bad_sig log_status delim

  if [ -z "$range" ]; then
    info "no commit range provided"
    return 0
  fi

  commit_count=$(git -C "$repo" rev-list --count "$range" 2>/dev/null || printf '0')
  if [ "$commit_count" -eq 0 ]; then
    info "no commits in range: $range"
    return 0
  fi

  sig_mismatch=0
  bad_sig=0
  log_status=0
  delim=$(printf '\037')
  if [ "$limit" -gt 0 ]; then
    while IFS="$delim" read -r short status signer author_name author_email subject; do
      printf '  • %s %s signer=%s author=%s <%s> %s\n' \
        "$short" "$status" "${signer:-unknown}" "$author_name" "$author_email" "$subject"
      if [ "$status" != "G" ]; then
        bad_sig=1
      fi
      if [ -n "${GIT_AUTHOR_EMAIL:-}" ] && [ "$author_email" = "$GIT_AUTHOR_EMAIL" ]; then
        case "$signer" in
          *"<$GIT_AUTHOR_EMAIL>"*) ;;
          *) sig_mismatch=1 ;;
        esac
      fi
    done < <(git -C "$repo" log -n "$limit" --format='%h%x1f%G?%x1f%GS%x1f%an%x1f%ae%x1f%s' "$range") || log_status=$?
  else
    while IFS="$delim" read -r short status signer author_name author_email subject; do
      printf '  • %s %s signer=%s author=%s <%s> %s\n' \
        "$short" "$status" "${signer:-unknown}" "$author_name" "$author_email" "$subject"
      if [ "$status" != "G" ]; then
        bad_sig=1
      fi
      if [ -n "${GIT_AUTHOR_EMAIL:-}" ] && [ "$author_email" = "$GIT_AUTHOR_EMAIL" ]; then
        case "$signer" in
          *"<$GIT_AUTHOR_EMAIL>"*) ;;
          *) sig_mismatch=1 ;;
        esac
      fi
    done < <(git -C "$repo" log --format='%h%x1f%G?%x1f%GS%x1f%an%x1f%ae%x1f%s' "$range") || log_status=$?
  fi

  if [ "$log_status" -ne 0 ]; then
    warn "git log failed for range: $range"
    return 0
  fi
  if [ "$bad_sig" -ne 0 ]; then
    warn "one or more checked commits are not good GPG signatures"
  else
    ok "checked commits have good GPG signatures"
  fi
  if [ "$sig_mismatch" -ne 0 ]; then
    warn "one or more commits authored by ${GIT_AUTHOR_EMAIL:-active author} appear signed by a different identity"
  fi
}

latest_semver_tag() {
  local repo="$1"
  git -C "$repo" tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-version:refname | sed -n '1p'
}

summarize() {
  if [ "$CHECKS_FAILED" -gt 0 ]; then
    printf '\nResult: FAIL (%s failure(s), %s warning(s))\n' "$CHECKS_FAILED" "$CHECKS_WARNED"
    return 1
  fi
  if [ "$CHECKS_WARNED" -gt 0 ]; then
    printf '\nResult: WARN (0 failures, %s warning(s))\n' "$CHECKS_WARNED"
    return 0
  fi
  printf '\nResult: OK\n'
  return 0
}
