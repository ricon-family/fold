#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load test_helper

setup() {
  TMPBIN="$BATS_TEST_TMPDIR/bin"
  HOME_REPO="$BATS_TEST_TMPDIR/desk/home"
  SECRET_LOG="$BATS_TEST_TMPDIR/secrets.log"
  EMAIL_LOG="$BATS_TEST_TMPDIR/emails.log"
  PASSWORD_CAPTURE="$BATS_TEST_TMPDIR/password.capture"
  mkdir -p "$TMPBIN" "$HOME_REPO"
  git init -q -b main "$HOME_REPO"
  git -C "$HOME_REPO" config user.name fixture
  git -C "$HOME_REPO" config user.email fixture@example.test
  git -C "$HOME_REPO" config commit.gpgsign false
  printf 'fixture home\n' > "$HOME_REPO/README.md"
  git -C "$HOME_REPO" add README.md
  git -C "$HOME_REPO" commit -q -m fixture
  : > "$SECRET_LOG"
  : > "$EMAIL_LOG"
  export TMPBIN HOME_REPO SECRET_LOG EMAIL_LOG PASSWORD_CAPTURE
  write_email_mocks
}

write_email_mocks() {
  cat > "$TMPBIN/secrets" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${SECRET_LOG:?}"
if [ "${1:-}" = get ] && [ "${2:-}" = test-agent/email-password ]; then
  printf 'fixture-email-password\n'
  exit 0
fi
echo "unexpected secrets command: $*" >&2
exit 2
SH
  chmod +x "$TMPBIN/secrets"
  export SECRETS="$TMPBIN/secrets"

  cat > "$TMPBIN/gpg" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = --list-secret-keys ] && [ "${2:-}" = test-agent@ricon.family ]; then
  exit 0
fi
echo "unexpected gpg command: $*" >&2
exit 2
SH
  chmod +x "$TMPBIN/gpg"
  export GPG="$TMPBIN/gpg"

  cat > "$TMPBIN/emails" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'args=%s config=%s himalaya=%s mise_diff=%s\n' \
  "$*" "${EMAILS_CONFIG:-unset}" "${HIMALAYA_CONFIG:-unset}" "${__MISE_DIFF:-unset}" \
  >> "${EMAIL_LOG:?}"
case "${1:-}" in
  account:setup)
    cat > "${PASSWORD_CAPTURE:?}"
    mkdir -p "$(dirname "${EMAILS_CONFIG:?}")"
    printf 'fixture-account=test-agent\n' > "$EMAILS_CONFIG"
    chmod 600 "$EMAILS_CONFIG"
    printf 'Email account configured: test-agent\n'
    ;;
  account:show)
    [ "${2:-}" = test-agent ] || exit 2
    grep -Fxq 'fixture-account=test-agent' "${EMAILS_CONFIG:?}" || exit 1
    cat <<EOF
Account:       test-agent
Address:       test-agent@ricon.family
Display name:  test-agent
Default:       true
IMAP host:     mail.ricon.family
SMTP host:     mail.ricon.family
Downloads dir: $(dirname "$EMAILS_CONFIG")/downloads/test-agent
GPG signing:   enabled
Config:        $EMAILS_CONFIG
EOF
    ;;
  *)
    echo "unexpected emails command: $*" >&2
    exit 2
    ;;
esac
SH
  chmod +x "$TMPBIN/emails"
  export EMAILS="$TMPBIN/emails"
}

@test "homes:email:setup dry-run retrieves no secret and writes nothing" {
  run fold_task homes:email:setup test-agent --home "$HOME_REPO"

  [ "$status" -eq 0 ]
  [[ "$output" == *"mode:   dry-run"* ]]
  [[ "$output" == *"test-agent/email-password"* ]]
  [ ! -e "$HOME_REPO/.emails/himalaya.toml" ]
  [ ! -s "$SECRET_LOG" ]
  [ ! -s "$EMAIL_LOG" ]
}

@test "homes:email:setup provisions and validates one ignored home-local account" {
  export EMAILS_CONFIG=/poison/other-agent.toml
  export HIMALAYA_CONFIG=/poison/global.toml
  export __MISE_DIFF=poisoned

  run fold_task homes:email:setup test-agent --home "$HOME_REPO" --yes

  [ "$status" -eq 0 ]
  [[ "$output" == *"Email ready: test-agent <test-agent@ricon.family>"* ]]
  [ "$(cat "$PASSWORD_CAPTURE")" = fixture-email-password ]
  [ "$(stat -f '%Lp' "$HOME_REPO/.emails/himalaya.toml" 2>/dev/null || stat -c '%a' "$HOME_REPO/.emails/himalaya.toml")" = 600 ]
  git -C "$HOME_REPO" check-ignore -q -- .emails/himalaya.toml
  [ -z "$(git -C "$HOME_REPO" status --short --untracked-files=all)" ]
  grep -Fx 'get test-agent/email-password' "$SECRET_LOG"
  grep -F "config=$HOME_REPO/.emails/himalaya.toml himalaya=unset mise_diff=unset" "$EMAIL_LOG"
}

@test "homes:email:setup is idempotent without retrieving the password again" {
  fold_task homes:email:setup test-agent --home "$HOME_REPO" --yes >/dev/null
  before=$(shasum -a 256 "$HOME_REPO/.emails/himalaya.toml" | awk '{print $1}')
  : > "$SECRET_LOG"
  : > "$EMAIL_LOG"

  run fold_task homes:email:setup test-agent --home "$HOME_REPO" --yes

  [ "$status" -eq 0 ]
  [[ "$output" == *"Email already ready"* ]]
  [ ! -s "$SECRET_LOG" ]
  grep -F 'args=account:show test-agent' "$EMAIL_LOG"
  after=$(shasum -a 256 "$HOME_REPO/.emails/himalaya.toml" | awk '{print $1}')
  [ "$before" = "$after" ]
}

@test "homes:email:setup refuses to replace an unexpected existing config" {
  mkdir -p "$HOME_REPO/.emails"
  printf 'fixture-account=wrong-agent\n' > "$HOME_REPO/.emails/himalaya.toml"
  chmod 600 "$HOME_REPO/.emails/himalaya.toml"
  before=$(shasum -a 256 "$HOME_REPO/.emails/himalaya.toml" | awk '{print $1}')

  run fold_task homes:email:setup test-agent --home "$HOME_REPO" --yes

  [ "$status" -ne 0 ]
  [[ "$output" == *"could not validate test-agent"* ]]
  [ ! -s "$SECRET_LOG" ]
  after=$(shasum -a 256 "$HOME_REPO/.emails/himalaya.toml" | awk '{print $1}')
  [ "$before" = "$after" ]
}
