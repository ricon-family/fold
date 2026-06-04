#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load test_helper

setup() {
  TMPBIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$TMPBIN"
  export TMPBIN
  FAKE_SECRET_STORE="$BATS_TEST_TMPDIR/secrets"
  mkdir -p "$FAKE_SECRET_STORE"
  export FAKE_SECRET_STORE
  write_fake_github_auth_secret_tools
  export SECRETS_BIN="$TMPBIN/secrets"
  export WEBSITES_BIN="$TMPBIN/websites"
}

write_fake_websites() {
  cat > "$TMPBIN/websites" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "$BATS_TEST_TMPDIR/websites-args"
printf '%s\n' "GITHUB_USERNAME=${GITHUB_USERNAME:-}" > "$BATS_TEST_TMPDIR/websites-env"
printf '%s\n' "GITHUB_PASSWORD=${GITHUB_PASSWORD:+set}" >> "$BATS_TEST_TMPDIR/websites-env"
out=""
prev=""
for arg in "$@"; do
  if [ "$prev" = "--out" ]; then
    out="$arg"
  fi
  prev="$arg"
done
[ -n "$out" ] || { echo 'missing --out' >&2; exit 1; }
printf '{"status":"enrolled","totp_seed":"JBSWY3DPEHPK3PXP","recovery_codes":["a1b2c-3d4e5","f6g7h-8i9j0"]}\n' > "$out"
printf 'TWO_FACTOR_RESULT:enrolled\n'
EOF
  chmod +x "$TMPBIN/websites"
}

@test "github:2fa:enroll stores enrollment material without printing secrets" {
  write_fake_websites

  run fold_task github:2fa:enroll --yes c0da

  [ "$status" -eq 0 ]
  [[ "$output" == *"✓ stored TOTP seed and 2 recovery code(s)"* ]]
  [ "$(cat "$FAKE_SECRET_STORE/c0da_github-totp")" = "JBSWY3DPEHPK3PXP" ]
  grep -q 'a1b2c-3d4e5' "$FAKE_SECRET_STORE/c0da_github-recovery-codes"
  grep -q 'github:2fa:enroll c0da --token-name c0da --out' "$BATS_TEST_TMPDIR/websites-args"
  grep -q '^GITHUB_USERNAME=c0da-ricon$' "$BATS_TEST_TMPDIR/websites-env"
  grep -q '^GITHUB_PASSWORD=set$' "$BATS_TEST_TMPDIR/websites-env"
  [[ "$output" != *"JBSWY3DPEHPK3PXP"* ]]
  [[ "$output" != *"a1b2c-3d4e5"* ]]
}

@test "github:2fa:enroll dry-run checks prerequisites without browser automation" {
  write_fake_websites

  run fold_task github:2fa:enroll --dry-run x1f9

  [ "$status" -eq 0 ]
  [[ "$output" == *"TOTP missing"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/websites-args" ]
}

@test "github:2fa:enroll requires visible approval" {
  write_fake_websites

  run fold_task github:2fa:enroll c0da

  [ "$status" -ne 0 ]
  [[ "$output" == *"rerun with --yes"* ]]
}

@test "github:2fa:enroll redacts credential material from browser diagnostics" {
  cat > "$TMPBIN/websites" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "diagnostic GITHUB_PASSWORD=${GITHUB_PASSWORD:-unset}" >&2
echo "diagnostic password ${GITHUB_PASSWORD:-unset}" >&2
echo "diagnostic bare totp 123456" >&2
echo "diagnostic seed JBSWY3DPEHPK3PXP" >&2
echo "diagnostic recovery a1b2c-3d4e5" >&2
exit 42
EOF
  chmod +x "$TMPBIN/websites"

  run fold_task github:2fa:enroll --yes c0da

  [ "$status" -ne 0 ]
  [[ "$output" == *"GITHUB_PASSWORD=[REDACTED]"* ]]
  [[ "$output" == *"password [REDACTED_PASSWORD]"* ]]
  [[ "$output" == *"bare totp [REDACTED_TOTP_CODE]"* ]]
  [[ "$output" == *"[REDACTED_BASE32]"* ]]
  [[ "$output" == *"[REDACTED_RECOVERY_CODE]"* ]]
  [[ "$output" != *"GITHUB_PASSWORD=password-for-c0da"* ]]
  [[ "$output" != *"password-for-c0da"* ]]
  [[ "$output" != *"bare totp 123456"* ]]
  [[ "$output" != *"JBSWY3DPEHPK3PXP"* ]]
  [[ "$output" != *"a1b2c-3d4e5"* ]]
}
