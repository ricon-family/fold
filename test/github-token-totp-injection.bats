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
  printf 'JBSWY3DPEHPK3PXP' > "$FAKE_SECRET_STORE/c0da_github-totp"
  export SECRETS_BIN="$TMPBIN/secrets"
  export WEBSITES_BIN="$TMPBIN/websites"
  export SHIMMER_BIN="$TMPBIN/shimmer"
  export GH_BIN="$TMPBIN/gh"
}

write_fake_websites() {
  local expected_task="$1"
  cat > "$TMPBIN/websites" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" > "\$BATS_TEST_TMPDIR/websites-args"
printf 'GITHUB_TOTP_CODE=%s\n' "\${GITHUB_TOTP_CODE:-}" > "\$BATS_TEST_TMPDIR/websites-env"
printf 'GITHUB_USERNAME=%s\n' "\${GITHUB_USERNAME:-}" >> "\$BATS_TEST_TMPDIR/websites-env"
if [ "\${1:-}" != "$expected_task" ]; then
  echo "unexpected websites task: \$*" >&2
  exit 1
fi
printf 'browser diagnostic\n' >&2
printf 'ghp_newtoken\n'
EOF
  chmod +x "$TMPBIN/websites"
}

write_fake_shimmer_and_gh() {
  cat > "$TMPBIN/shimmer" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/shimmer-log"
if [ "${1:-}" = "github:token:store" ]; then
  key="${2:?agent}/github-pat"
  path="$FAKE_SECRET_STORE/$(printf '%s' "$key" | tr '/' '__')"
  printf '%s' "${3:?token}" > "$path"
  exit 0
fi
echo "unexpected shimmer command: $*" >&2
exit 1
EOF
  chmod +x "$TMPBIN/shimmer"

  cat > "$TMPBIN/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/gh-log"
printf 'c0da-ricon\n'
EOF
  chmod +x "$TMPBIN/gh"
}

@test "github:token:create injects caller-generated TOTP code when stored seed exists" {
  write_fake_websites github:token:create
  write_fake_shimmer_and_gh

  run fold_task github:token:create --yes --no-sync-ci c0da

  [ "$status" -eq 0 ]
  grep -q '^GITHUB_TOTP_CODE=123456$' "$BATS_TEST_TMPDIR/websites-env"
  grep -q '^GITHUB_USERNAME=c0da-ricon$' "$BATS_TEST_TMPDIR/websites-env"
  grep -q 'github:token:create c0da --login-id c0da' "$BATS_TEST_TMPDIR/websites-args"
  grep -q 'github:token:store c0da ghp_newtoken' "$BATS_TEST_TMPDIR/shimmer-log"
  [[ "$output" == *"✓ verified as c0da-ricon"* ]]
}

@test "github:token:rotate injects caller-generated TOTP code when stored seed exists" {
  write_fake_websites github:token:rotate
  write_fake_shimmer_and_gh

  run fold_task github:token:rotate --yes --no-sync-ci c0da

  [ "$status" -eq 0 ]
  grep -q '^GITHUB_TOTP_CODE=123456$' "$BATS_TEST_TMPDIR/websites-env"
  grep -q 'github:token:rotate c0da --login-id c0da' "$BATS_TEST_TMPDIR/websites-args"
  grep -q 'github:token:store c0da ghp_newtoken' "$BATS_TEST_TMPDIR/shimmer-log"
  [[ "$output" == *"✓ verified as c0da-ricon"* ]]
}

@test "github:token:create fails before browser automation when TOTP generation fails" {
  export FAKE_TOTP_FAIL=true
  write_fake_websites github:token:create
  write_fake_shimmer_and_gh

  run fold_task github:token:create --yes --no-sync-ci c0da

  [ "$status" -ne 0 ]
  [[ "$output" == *"totp failed intentionally"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/websites-args" ]
  [ ! -e "$BATS_TEST_TMPDIR/shimmer-log" ]
}

@test "github:token:rotate fails before browser automation when TOTP generation fails" {
  export FAKE_TOTP_FAIL=true
  write_fake_websites github:token:rotate
  write_fake_shimmer_and_gh

  run fold_task github:token:rotate --yes --no-sync-ci c0da

  [ "$status" -ne 0 ]
  [[ "$output" == *"totp failed intentionally"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/websites-args" ]
  [ ! -e "$BATS_TEST_TMPDIR/shimmer-log" ]
}

@test "github:token:create redacts credential material from browser diagnostics" {
  cat > "$TMPBIN/websites" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "diagnostic GITHUB_TOTP_CODE=${GITHUB_TOTP_CODE:-unset}" >&2
echo "diagnostic bare totp ${GITHUB_TOTP_CODE:-unset}" >&2
echo "diagnostic password ${GITHUB_PASSWORD:-unset}" >&2
echo "diagnostic seed JBSWY3DPEHPK3PXP" >&2
echo "diagnostic recovery a1b2c-3d4e5" >&2
exit 42
EOF
  chmod +x "$TMPBIN/websites"
  write_fake_shimmer_and_gh

  run fold_task github:token:create --yes --no-sync-ci c0da

  [ "$status" -ne 0 ]
  [[ "$output" == *"GITHUB_TOTP_CODE=[REDACTED_TOTP_CODE]"* ]]
  [[ "$output" == *"bare totp [REDACTED_TOTP_CODE]"* ]]
  [[ "$output" == *"password [REDACTED_PASSWORD]"* ]]
  [[ "$output" == *"[REDACTED_BASE32]"* ]]
  [[ "$output" == *"[REDACTED_RECOVERY_CODE]"* ]]
  [[ "$output" != *"GITHUB_TOTP_CODE=123456"* ]]
  [[ "$output" != *"bare totp 123456"* ]]
  [[ "$output" != *"password-for-c0da"* ]]
  [[ "$output" != *"JBSWY3DPEHPK3PXP"* ]]
  [[ "$output" != *"a1b2c-3d4e5"* ]]
}

@test "github:token:rotate redacts credential material from browser diagnostics" {
  cat > "$TMPBIN/websites" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "diagnostic GITHUB_TOTP_CODE=${GITHUB_TOTP_CODE:-unset}" >&2
echo "diagnostic bare totp ${GITHUB_TOTP_CODE:-unset}" >&2
echo "diagnostic password ${GITHUB_PASSWORD:-unset}" >&2
echo "diagnostic seed JBSWY3DPEHPK3PXP" >&2
echo "diagnostic recovery a1b2c-3d4e5" >&2
exit 42
EOF
  chmod +x "$TMPBIN/websites"
  write_fake_shimmer_and_gh

  run fold_task github:token:rotate --yes --no-sync-ci c0da

  [ "$status" -ne 0 ]
  [[ "$output" == *"GITHUB_TOTP_CODE=[REDACTED_TOTP_CODE]"* ]]
  [[ "$output" == *"bare totp [REDACTED_TOTP_CODE]"* ]]
  [[ "$output" == *"password [REDACTED_PASSWORD]"* ]]
  [[ "$output" == *"[REDACTED_BASE32]"* ]]
  [[ "$output" == *"[REDACTED_RECOVERY_CODE]"* ]]
  [[ "$output" != *"GITHUB_TOTP_CODE=123456"* ]]
  [[ "$output" != *"bare totp 123456"* ]]
  [[ "$output" != *"password-for-c0da"* ]]
  [[ "$output" != *"JBSWY3DPEHPK3PXP"* ]]
  [[ "$output" != *"a1b2c-3d4e5"* ]]
}
