#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

load test_helper

setup() {
  TMPBIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$TMPBIN"
  export TMPBIN
  export PATH="$TMPBIN:$PATH"
  export SECRETS_BIN="$TMPBIN/secrets"
  export GH_BIN="$TMPBIN/gh"
}

write_pat_only_fake_secrets() {
  cat > "$TMPBIN/secrets" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/secrets-log"
if [ "${1:-}" != "get" ]; then
  echo "unexpected secrets command: $*" >&2
  exit 2
fi
case "${2:-}" in
  quick/github-pat) printf 'operator-token' ;;
  baby-joel/github-pat) printf 'pat-baby-joel' ;;
  x1f9/github-pat) printf 'pat-x1f9' ;;
  zeke/github-pat) printf 'pat-zeke' ;;
  missing/github-pat) exit 1 ;;
  empty/github-pat) : ;;
  *) echo "missing secret: ${2:-}" >&2; exit 1 ;;
esac
SH
  chmod +x "$TMPBIN/secrets"
}

write_pat_only_fake_gh() {
  cat > "$TMPBIN/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
stdin=$(cat)
{
  printf 'GH_TOKEN=%s\n' "${GH_TOKEN:-}"
  printf 'ARGS=%s\n' "$*"
  printf 'STDIN=%s\n' "$stdin"
} >> "$BATS_TEST_TMPDIR/gh-log"
if [ "${FAIL_SECRET:-}" = "${3:-}" ]; then
  echo "intentional failure containing $stdin" >&2
  exit 44
fi
[ "${1:-}" = "secret" ]
[ "${2:-}" = "set" ]
[ -n "${3:-}" ]
[ "${4:-}" = "--repo" ]
[ -n "${5:-}" ]
SH
  chmod +x "$TMPBIN/gh"
}

@test "dry-run reports normalized PAT secret names without reading credentials" {
  cat > "$TMPBIN/secrets" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "secrets should not be called in dry-run" >> "$BATS_TEST_TMPDIR/secrets-called"
exit 99
SH
  chmod +x "$TMPBIN/secrets"
  cat > "$TMPBIN/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "gh should not be called in dry-run" >> "$BATS_TEST_TMPDIR/gh-called"
exit 99
SH
  chmod +x "$TMPBIN/gh"

  run fold_task github:token:sync-ci-pat-only --dry-run baby-joel x1f9

  [ "$status" -eq 0 ]
  [[ "$output" == *"baby-joel -> BABY_JOEL_GITHUB_PAT"* ]]
  [[ "$output" == *"x1f9 -> X1F9_GITHUB_PAT"* ]]
  [[ "$output" == *"No credentials were read"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/secrets-called" ]
  [ ! -e "$BATS_TEST_TMPDIR/gh-called" ]
}

@test "sync writes only PAT secret values via stdin and does not print PATs" {
  write_pat_only_fake_secrets
  write_pat_only_fake_gh

  run fold_task github:token:sync-ci-pat-only --operator quick baby-joel x1f9

  [ "$status" -eq 0 ]
  [[ "$output" == *"✓ baby-joel -> BABY_JOEL_GITHUB_PAT"* ]]
  [[ "$output" == *"✓ x1f9 -> X1F9_GITHUB_PAT"* ]]
  [[ "$output" == *"PAT-only CI sync complete"* ]]
  [[ "$output" != *"pat-baby-joel"* ]]
  [[ "$output" != *"pat-x1f9"* ]]
  grep -q '^ARGS=secret set BABY_JOEL_GITHUB_PAT --repo ricon-family/fold$' "$BATS_TEST_TMPDIR/gh-log"
  grep -q '^ARGS=secret set X1F9_GITHUB_PAT --repo ricon-family/fold$' "$BATS_TEST_TMPDIR/gh-log"
  grep -q '^STDIN=pat-baby-joel$' "$BATS_TEST_TMPDIR/gh-log"
  grep -q '^STDIN=pat-x1f9$' "$BATS_TEST_TMPDIR/gh-log"
  ! grep -q 'B2\|EMAIL\|MATRIX\|GPG' "$BATS_TEST_TMPDIR/gh-log"
}

@test "--repo overrides the target repository" {
  write_pat_only_fake_secrets
  write_pat_only_fake_gh

  run fold_task github:token:sync-ci-pat-only --operator quick --repo ricon-family/den x1f9

  [ "$status" -eq 0 ]
  grep -q '^ARGS=secret set X1F9_GITHUB_PAT --repo ricon-family/den$' "$BATS_TEST_TMPDIR/gh-log"
}

@test "multi-agent sync reports every agent and fails nonzero on any write failure" {
  write_pat_only_fake_secrets
  write_pat_only_fake_gh
  export FAIL_SECRET=ZEKE_GITHUB_PAT

  run fold_task github:token:sync-ci-pat-only --operator quick baby-joel zeke x1f9

  [ "$status" -ne 0 ]
  [[ "$output" == *"✓ baby-joel -> BABY_JOEL_GITHUB_PAT"* ]]
  [[ "$output" == *"✗ zeke -> ZEKE_GITHUB_PAT: gh secret set failed"* ]]
  [[ "$output" == *"✓ x1f9 -> X1F9_GITHUB_PAT"* ]]
  [[ "$output" == *"completed with 1 failure"* ]]
  [[ "$output" != *"pat-zeke"* ]]
}

@test "missing operator and PAT failures are clear" {
  write_pat_only_fake_secrets
  write_pat_only_fake_gh

  run fold_task github:token:sync-ci-pat-only baby-joel
  [ "$status" -ne 0 ]
  [[ "$output" == *"--operator <agent> is required"* ]]

  run fold_task github:token:sync-ci-pat-only --operator quick missing empty
  [ "$status" -ne 0 ]
  [[ "$output" == *"✗ missing -> MISSING_GITHUB_PAT: missing missing/github-pat"* ]]
  [[ "$output" == *"✗ empty -> EMPTY_GITHUB_PAT: empty/github-pat is empty"* ]]
}
