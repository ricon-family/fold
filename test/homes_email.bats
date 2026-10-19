#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load test_helper

setup() {
  TMPBIN="$BATS_TEST_TMPDIR/bin"
  HOME_REPO="$BATS_TEST_TMPDIR/desk/home"
  export EMAIL_LOG="$BATS_TEST_TMPDIR/emails.log"
  export SECRET_LOG="$BATS_TEST_TMPDIR/secrets.log"
  export PASSWORD_CAPTURE="$BATS_TEST_TMPDIR/credentials"
  export SIGNER=1234567890ABCDEF1234567890ABCDEF12345678
  mkdir -p "$TMPBIN" "$HOME_REPO"
  git init -q -b main "$HOME_REPO"
  : > "$EMAIL_LOG"
  : > "$SECRET_LOG"

  export EMAIL_ACCOUNTS=personal EMAIL_DEFAULT_ACCOUNT=personal
  export EMAIL_PERSONAL_ADDRESS=mailbox@example.test EMAIL_PERSONAL_DISPLAY_NAME='Mailbox Owner'
  export EMAIL_PERSONAL_SIGNING_FINGERPRINT="$SIGNER"
  export EMAIL_PERSONAL_IMAP_HOST=imap.example.test EMAIL_PERSONAL_IMAP_PORT=993 EMAIL_PERSONAL_IMAP_ENCRYPTION=tls
  export EMAIL_PERSONAL_IMAP_USERNAME=reader EMAIL_PERSONAL_IMAP_PASSWORD=incoming-fixture
  export EMAIL_PERSONAL_SMTP_HOST=smtp.example.test EMAIL_PERSONAL_SMTP_PORT=587 EMAIL_PERSONAL_SMTP_ENCRYPTION=starttls
  export EMAIL_PERSONAL_SMTP_USERNAME=sender EMAIL_PERSONAL_SMTP_PASSWORD=outgoing-fixture

  cat > "$TMPBIN/secrets" <<'SH'
#!/usr/bin/env bash
printf 'unexpected secret access\n' >> "$SECRET_LOG"
exit 1
SH
  cat > "$TMPBIN/gpg" <<'SH'
#!/usr/bin/env bash
[ "${FAKE_GPG_FAIL:-false}" != true ] || exit 1
[ "$*" = "--batch --with-colons --list-secret-keys -- $SIGNER" ] || exit 2
printf 'sec:u:4096:1:key:0:0:::::scESC:::+:\nfpr:::::::::%s:\n' "${FAKE_FPR:-$SIGNER}"
SH
  cat > "$TMPBIN/emails" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[ "$1" = account:setup ] || exit 2
printf 'args=%s himalaya=%s mise_diff=%s\n' "$*" "${HIMALAYA_CONFIG:-unset}" "${__MISE_DIFF:-unset}" >> "$EMAIL_LOG"
[ "${FAIL_ACCOUNT:-}" != "$2" ] || exit 1
credentials=$(cat)
if [ -n "${RACE_DIRECTORY:-}" ]; then mkdir -p "$RACE_DIRECTORY"; fi
printf '%s\n' "$credentials" > "$PASSWORD_CAPTURE.$2"
# Deterministic synthetic serialization tests Fold policy, not Emails' TOML renderer.
printf '%s\n%s\n' "$*" "$credentials" >> "$EMAILS_CONFIG"
chmod 600 "$EMAILS_CONFIG"
SH
  chmod +x "$TMPBIN/"*
  export SECRETS="$TMPBIN/secrets" GPG="$TMPBIN/gpg" EMAILS="$TMPBIN/emails"
}

add_work_account() {
  export EMAIL_ACCOUNTS='personal work' EMAIL_DEFAULT_ACCOUNT=work
  export EMAIL_WORK_ADDRESS=other@company.test EMAIL_WORK_DISPLAY_NAME='Company Mail'
  export EMAIL_WORK_SIGNING_FINGERPRINT="$SIGNER"
  export EMAIL_WORK_IMAP_HOST=in.company.test EMAIL_WORK_IMAP_PORT=143 EMAIL_WORK_IMAP_ENCRYPTION=starttls
  export EMAIL_WORK_IMAP_USERNAME=company-reader EMAIL_WORK_IMAP_PASSWORD=work-incoming
  export EMAIL_WORK_SMTP_HOST=out.company.test EMAIL_WORK_SMTP_PORT=465 EMAIL_WORK_SMTP_ENCRYPTION=tls
  export EMAIL_WORK_SMTP_USERNAME=company-sender EMAIL_WORK_SMTP_PASSWORD=work-outgoing
}

@test "homes:email:setup dry-run validates environment without secret retrieval or writes" {
  export AGENT_HOME="$HOME_REPO"
  run fold_task homes:email:setup test-agent

  [ "$status" -eq 0 ]
  [[ "$output" == *"home:   $HOME_REPO"* ]]
  [[ "$output" == *'mode:   dry-run'* ]]
  [ ! -e "$HOME_REPO/.emails" ]
  [ ! -s "$SECRET_LOG" ]
  [ ! -s "$EMAIL_LOG" ]
}

@test "homes:email:setup forwards distinct transport credentials and exact signer to Emails" {
  export EMAILS_CONFIG=/poison/other-agent.toml HIMALAYA_CONFIG=/poison/global.toml __MISE_DIFF=poisoned

  run fold_task homes:email:setup test-agent --home "$HOME_REPO" --yes

  [ "$status" -eq 0 ]
  [[ "$output" != *incoming-fixture* && "$output" != *outgoing-fixture* ]]
  jq -e '.imap.username == "reader" and .imap.password == "incoming-fixture" and .smtp.username == "sender" and .smtp.password == "outgoing-fixture"' "$PASSWORD_CAPTURE.personal"
  grep -F -- '--address mailbox@example.test' "$EMAIL_LOG"
  grep -F -- "--gpg-fingerprint $SIGNER" "$EMAIL_LOG"
  grep -F -- '--smtp-encryption starttls' "$EMAIL_LOG"
  grep -F 'himalaya=unset mise_diff=unset' "$EMAIL_LOG"
  [ ! -s "$SECRET_LOG" ]
  git -C "$HOME_REPO" check-ignore -q -- .emails/himalaya.toml
  [ -z "$(git -C "$HOME_REPO" status --short --untracked-files=all)" ]
}

@test "homes:email:setup provisions every declared account with exactly the declared default" {
  add_work_account
  run fold_task homes:email:setup test-agent --home "$HOME_REPO" --yes

  [ "$status" -eq 0 ]
  [ "$(grep -c 'args=account:setup' "$EMAIL_LOG")" -eq 2 ]
  grep 'args=account:setup work .*--set-default' "$EMAIL_LOG"
  ! grep 'args=account:setup personal .*--set-default' "$EMAIL_LOG"
  jq -e '.imap.password == "work-incoming" and .smtp.password == "work-outgoing"' "$PASSWORD_CAPTURE.work"
}

@test "homes:email:setup validates existing matching config without rewriting it" {
  fold_task homes:email:setup test-agent --home "$HOME_REPO" --yes
  before=$(shasum -a 256 "$HOME_REPO/.emails/himalaya.toml")
  run fold_task homes:email:setup test-agent --home "$HOME_REPO" --yes

  [ "$status" -eq 0 ]
  [[ "$output" == *'Email already ready'* ]]
  [ "$before" = "$(shasum -a 256 "$HOME_REPO/.emails/himalaya.toml")" ]
  [ ! -s "$SECRET_LOG" ]
}

@test "homes:email:setup preserves differing existing config and its credentials" {
  fold_task homes:email:setup test-agent --home "$HOME_REPO" --yes
  before=$(shasum -a 256 "$HOME_REPO/.emails/himalaya.toml")
  export EMAIL_PERSONAL_SMTP_PASSWORD=changed-fixture
  run fold_task homes:email:setup test-agent --home "$HOME_REPO" --yes

  [ "$status" -ne 0 ]
  [[ "$output" == *'preserved unchanged'* ]]
  [ "$before" = "$(shasum -a 256 "$HOME_REPO/.emails/himalaya.toml")" ]
}

@test "homes:email:setup validates all accounts before any setup call" {
  add_work_account
  unset EMAIL_WORK_SMTP_PASSWORD
  run fold_task homes:email:setup test-agent --home "$HOME_REPO" --yes

  [ "$status" -ne 0 ]
  [ ! -s "$EMAIL_LOG" ]
  [ ! -e "$HOME_REPO/.emails" ]
}

@test "homes:email:setup rejects absent duplicate and invalid default account selections" {
  for selection in missing duplicate default; do
    case "$selection" in
      missing) unset EMAIL_ACCOUNTS ;;
      duplicate) export EMAIL_ACCOUNTS='personal personal' ;;
      default) export EMAIL_ACCOUNTS=personal EMAIL_DEFAULT_ACCOUNT=undeclared ;;
    esac
    run fold_task homes:email:setup test-agent --home "$HOME_REPO" --yes

    [ "$status" -ne 0 ]
    [ ! -s "$EMAIL_LOG" ]
    [ ! -e "$HOME_REPO/.emails" ]
  done
}

@test "homes:email:setup refuses missing or inexact secret signing keys before writes" {
  export FAKE_GPG_FAIL=true
  run fold_task homes:email:setup test-agent --home "$HOME_REPO" --yes
  [ "$status" -ne 0 ]
  [ ! -e "$HOME_REPO/.emails" ]

  unset FAKE_GPG_FAIL
  export FAKE_FPR=FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
  run fold_task homes:email:setup test-agent --home "$HOME_REPO" --yes
  [ "$status" -ne 0 ]
  [ ! -e "$HOME_REPO/.emails" ]
}

@test "homes:email:setup does not publish a partial config when a later account fails" {
  add_work_account
  export FAIL_ACCOUNT=work
  run fold_task homes:email:setup test-agent --home "$HOME_REPO" --yes

  [ "$status" -ne 0 ]
  [ ! -e "$HOME_REPO/.emails/himalaya.toml" ]
  [ -z "$(find "$HOME_REPO/.emails" -name '.setup.*' -print)" ]
}

@test "homes:email:setup refuses a raced-in destination directory without writing into it" {
  export RACE_DIRECTORY="$HOME_REPO/.emails/himalaya.toml"
  run fold_task homes:email:setup test-agent --home "$HOME_REPO" --yes

  [ "$status" -ne 0 ]
  [ -d "$RACE_DIRECTORY" ]
  [ -z "$(find "$RACE_DIRECTORY" -type f -print)" ]
  [[ "$output" == *'destination appeared during setup'* ]]
}

@test "homes:email:setup refuses symlinked or multiply linked config files" {
  mkdir -p "$HOME_REPO/.emails"
  printf 'preserve\n' > "$BATS_TEST_TMPDIR/original"
  chmod 600 "$BATS_TEST_TMPDIR/original"
  ln -s "$BATS_TEST_TMPDIR/original" "$HOME_REPO/.emails/himalaya.toml"
  run fold_task homes:email:setup test-agent --home "$HOME_REPO" --yes
  [ "$status" -ne 0 ]
  [ ! -s "$EMAIL_LOG" ]

  rm "$HOME_REPO/.emails/himalaya.toml"
  ln "$BATS_TEST_TMPDIR/original" "$HOME_REPO/.emails/himalaya.toml"
  run fold_task homes:email:setup test-agent --home "$HOME_REPO" --yes
  [ "$status" -ne 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/original")" = preserve ]
  [ ! -s "$EMAIL_LOG" ]
}
