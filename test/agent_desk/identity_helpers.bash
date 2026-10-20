write_fake_gh() {
  cat > "$TMPBIN/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = api ] && [ "${2:-}" = user ] && [ "${3:-}" = --jq ] && [ "${4:-}" = .login ]; then
  [ "${GH_TOKEN:-}" = quick-target-token ] || {
    echo "wrong GitHub token" >&2
    exit 1
  }
  printf '%s\n' "${FAKE_GITHUB_LOGIN:-quick-ricon}"
  exit 0
fi
echo "unexpected gh command: $*" >&2
exit 2
SH
  chmod +x "$TMPBIN/gh"
  export GH_BIN="$TMPBIN/gh"
}

write_target_identity_shimmer() {
  cat > "$TMPBIN/shimmer" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  as)
    if [ "${REQUIRE_LAUNCH_CONTEXT_RESET:-false}" = true ]; then
      [ -z "${AGENT_HOME:-}" ]
      [ -z "${AGENT_IDENTITY:-}" ]
      [ -z "${CHAT_IDENTITY:-}" ]
      [ -z "${EMAILS_CONFIG:-}" ]
      [ -z "${HIMALAYA_CONFIG:-}" ]
      [ -z "${GITHUB_TOKEN:-}" ]
      [ -z "${GH_CONFIG_DIR:-}" ]
      [ -z "${GIT_DIR:-}" ]
      [ -z "${GIT_WORK_TREE:-}" ]
      [ -z "${GIT_COMMON_DIR:-}" ]
      [ -z "${__MISE_DIFF:-}" ]
    fi
    if [ -n "${SHIMMER_ACTIVATE_LIB:-}" ]; then
      source "$SHIMMER_ACTIVATE_LIB"
      persona_activate "${2:?persona required}"
      exit
    fi
    if [ -n "${FAKE_IDENTITY_HOME:-}" ]; then
      printf 'export AGENT_HOME=%q\n' "$FAKE_IDENTITY_HOME"
    fi
    printf 'export GIT_AUTHOR_NAME=%q\n' "${FAKE_ACTIVE_NAME:-quick}"
    printf 'export GIT_AUTHOR_EMAIL=%q\n' "${FAKE_ACTIVE_EMAIL:-quick@ricon.family}"
    printf 'export GIT_COMMITTER_NAME=%q\n' "${FAKE_ACTIVE_NAME:-quick}"
    printf 'export GIT_COMMITTER_EMAIL=%q\n' "${FAKE_ACTIVE_EMAIL:-quick@ricon.family}"
    printf 'export GH_TOKEN=quick-target-token\n'
    printf 'export GIT_CONFIG_COUNT=4\n'
    printf 'export GIT_CONFIG_KEY_0=user.name\n'
    printf 'export GIT_CONFIG_VALUE_0=%q\n' "${FAKE_ACTIVE_NAME:-quick}"
    printf 'export GIT_CONFIG_KEY_1=user.email\n'
    printf 'export GIT_CONFIG_VALUE_1=%q\n' "${FAKE_ACTIVE_EMAIL:-quick@ricon.family}"
    printf 'export GIT_CONFIG_KEY_2=user.signingkey\n'
    printf 'export GIT_CONFIG_VALUE_2=%q\n' "${FAKE_ACTIVE_SIGNING_KEY:-AABBCCDDEEFF0011}"
    printf 'export GIT_CONFIG_KEY_3=commit.gpgsign\n'
    printf 'export GIT_CONFIG_VALUE_3=true\n'
    ;;
  agent)
    {
      printf 'CWD=%s\n' "$(pwd -P)"
      printf 'AGENT_HOME=%s\n' "${AGENT_HOME:-unset}"
      printf 'AGENT_IDENTITY=%s\n' "${AGENT_IDENTITY:-unset}"
      printf 'CHAT_IDENTITY=%s\n' "${CHAT_IDENTITY:-unset}"
      printf 'EMAILS_CONFIG=%s\n' "${EMAILS_CONFIG:-unset}"
      printf 'HIMALAYA_CONFIG=%s\n' "${HIMALAYA_CONFIG:-unset}"
      printf '__MISE_DIFF=%s\n' "${__MISE_DIFF:-unset}"
      printf 'GIT_AUTHOR_NAME=%s\n' "${GIT_AUTHOR_NAME:-unset}"
      printf 'GIT_AUTHOR_EMAIL=%s\n' "${GIT_AUTHOR_EMAIL:-unset}"
      printf 'GIT_COMMITTER_NAME=%s\n' "${GIT_COMMITTER_NAME:-unset}"
      printf 'GIT_COMMITTER_EMAIL=%s\n' "${GIT_COMMITTER_EMAIL:-unset}"
      printf 'GIT_SIGNING_KEY=%s\n' "$(git config --get user.signingkey)"
      printf 'GH_TOKEN=%s\n' "${GH_TOKEN:-unset}"
      printf 'MODEL=%s\n' "${3:-}"
      printf 'PACKET=%s\n' "$AGENT_DESK_PACKET"
      printf 'EMAIL_ACCOUNTS=%s\n' "${EMAIL_ACCOUNTS:-unset}"
      printf 'EMAIL_LEGACY_IMAP_PASSWORD=%s\n' "${EMAIL_LEGACY_IMAP_PASSWORD:-unset}"
      printf 'BLOBS_ACCOUNTS=%s\n' "${BLOBS_ACCOUNTS:-unset}"
      printf 'BLOBS_LEGACY_APPLICATION_KEY=%s\n' "${BLOBS_LEGACY_APPLICATION_KEY:-unset}"
      printf 'CORE_EDITOR=%s\n' "$(git config --get --default unset core.editor)"
      printf 'UNRELATED_SETTING=%s\n' "${UNRELATED_SETTING:-unset}"
    } > "${AGENT_LOG:?}"
    if [ -n "${AGENT_MESSAGE_LOG:-}" ]; then
      printf '%s' "${4:-}" > "$AGENT_MESSAGE_LOG"
    fi
    ;;
  *) exit 2 ;;
esac
SH
  chmod +x "$TMPBIN/shimmer"
}

write_resume_sessions() {
  export SESSIONS_LOG="$BATS_TEST_TMPDIR/sessions.log"
  export SESSIONS_ENV_LOG="$BATS_TEST_TMPDIR/sessions-env.log"
  cat > "$TMPBIN/sessions" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'sessions %s\n' "$*" >> "${SESSIONS_LOG:?}"
if [ "${1:-}" = wake ]; then
  {
    printf 'CWD=%s\n' "$(pwd -P)"
    printf 'AGENT_HOME=%s\n' "${AGENT_HOME:-unset}"
    printf 'EMAILS_CONFIG=%s\n' "${EMAILS_CONFIG:-unset}"
    printf 'HIMALAYA_CONFIG=%s\n' "${HIMALAYA_CONFIG:-unset}"
    printf 'AGENT_IDENTITY=%s\n' "${AGENT_IDENTITY:-unset}"
    printf 'CHAT_IDENTITY=%s\n' "${CHAT_IDENTITY:-unset}"
    printf 'GIT_AUTHOR_NAME=%s\n' "${GIT_AUTHOR_NAME:-unset}"
    printf 'GIT_AUTHOR_EMAIL=%s\n' "${GIT_AUTHOR_EMAIL:-unset}"
    printf 'GIT_COMMITTER_NAME=%s\n' "${GIT_COMMITTER_NAME:-unset}"
    printf 'GIT_COMMITTER_EMAIL=%s\n' "${GIT_COMMITTER_EMAIL:-unset}"
    printf 'GH_TOKEN=%s\n' "${GH_TOKEN:-unset}"
    printf 'GIT_CONFIG_COUNT=%s\n' "${GIT_CONFIG_COUNT:-unset}"
    printf 'GIT_SIGNING_KEY=%s\n' "$(git config --get user.signingkey)"
    printf 'EMAIL_ACCOUNTS=%s\n' "${EMAIL_ACCOUNTS:-unset}"
    printf 'EMAIL_LEGACY_IMAP_PASSWORD=%s\n' "${EMAIL_LEGACY_IMAP_PASSWORD:-unset}"
    printf 'BLOBS_ACCOUNTS=%s\n' "${BLOBS_ACCOUNTS:-unset}"
    printf 'BLOBS_LEGACY_APPLICATION_KEY=%s\n' "${BLOBS_LEGACY_APPLICATION_KEY:-unset}"
    printf 'CORE_EDITOR=%s\n' "$(git config --get --default unset core.editor)"
    printf 'UNRELATED_SETTING=%s\n' "${UNRELATED_SETTING:-unset}"
  } > "${SESSIONS_ENV_LOG:?}"
  exit 0
fi
echo "unexpected sessions command: $*" >&2
exit 2
SH
  chmod +x "$TMPBIN/sessions"
  export SESSIONS_BIN="$TMPBIN/sessions"
}

setup_switching_personas() {
  local variable persona shimmer_root

  # Isolate this fixture process; the production runtime must preserve ownership.
  while IFS= read -r variable; do
    case "$variable" in GIT_CONFIG_*|EMAIL_*|BLOBS_*) unset "$variable" ;; esac
  done < <(compgen -A variable)
  unset SHIMMER_PERSONA_STATE GH_TOKEN GITHUB_TOKEN GH_CONFIG_DIR
  unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL

  shimmer_root=$(mise -C "$REPO_DIR" where shiv:shimmer)
  export SHIMMER_ACTIVATE_LIB="$shimmer_root/packages/shimmer/lib/persona/activate.sh"
  export FIXTURE_PERSONAS="$BATS_TEST_TMPDIR/personas"
  export FIXTURE_SIGNER=11223344556677889900AABBAABBCCDDEEFF0011
  mkdir -p "$FIXTURE_PERSONAS"

  for persona in junior quick; do
    jq -n --arg agent "$persona" --arg signer "$FIXTURE_SIGNER" '{
      ($agent + "/git/name"): $agent,
      ($agent + "/git/email"): ($agent + "@ricon.family"),
      ($agent + "/git/signing-fingerprint"): $signer,
      ($agent + "/github/token"): ($agent + "-target-token")
    } + (if $agent == "junior" then {
      "junior/email/accounts": "legacy",
      "junior/email/default-account": "legacy",
      "junior/email/legacy/address": "junior@example.test",
      "junior/email/legacy/display-name": "Junior",
      "junior/email/legacy/imap/host": "imap.example.test",
      "junior/email/legacy/imap/port": "993",
      "junior/email/legacy/imap/encryption": "tls",
      "junior/email/legacy/imap/username": "junior",
      "junior/email/legacy/imap/password": "old-imap-password",
      "junior/email/legacy/smtp/host": "smtp.example.test",
      "junior/email/legacy/smtp/port": "465",
      "junior/email/legacy/smtp/encryption": "tls",
      "junior/email/legacy/smtp/username": "junior",
      "junior/email/legacy/smtp/password": "old-smtp-password",
      "junior/email/legacy/signing-fingerprint": $signer,
      "junior/blobs/accounts": "legacy",
      "junior/blobs/default-account": "legacy",
      "junior/blobs/legacy/provider": "b2",
      "junior/blobs/legacy/bucket": "old-bucket",
      "junior/blobs/legacy/key-id": "old-key-id",
      "junior/blobs/legacy/application-key": "old-blob-key"
    } else {} end)' > "$FIXTURE_PERSONAS/$persona.json"
  done

  cat > "$TMPBIN/secrets" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[ "${1:-}" = export ] && [ "${2:-}" = --prefix ] || exit 2
case "${3:-}" in
  junior/|quick/) cat "$FIXTURE_PERSONAS/${3%/}.json" ;;
  *) exit 2 ;;
esac
SH
  cat > "$TMPBIN/gpg" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ " $* " == *" --list-secret-keys "* ]] || exit 2
printf 'sec:u:4096:1:AABBCCDDEEFF0011:0:0:::::s:::\n'
printf 'fpr:::::::::%s:\n' "$FIXTURE_SIGNER"
SH
  chmod +x "$TMPBIN/secrets" "$TMPBIN/gpg"
  write_target_identity_shimmer
}
