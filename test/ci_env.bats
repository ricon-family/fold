#!/usr/bin/env bats

load test_helper

@test "ci:env sanitizes an authenticated home clone before agent setup" {
  mock_bin="$BATS_TEST_TMPDIR/bin"
  mock_log="$BATS_TEST_TMPDIR/mock.log"
  home="$BATS_TEST_TMPDIR/agents/test-agent/home"
  github_env="$BATS_TEST_TMPDIR/github-env"
  token=ghp_test_secret_that_must_not_persist
  real_git=$(command -v git)
  real_mise=$(command -v mise)
  mkdir -p "$mock_bin"
  : > "$mock_log"
  : > "$github_env"

  cat > "$mock_bin/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'gh' >> "$MOCK_LOG"
printf '\t%s' "$@" >> "$MOCK_LOG"
printf '\n' >> "$MOCK_LOG"

case "${1:-} ${2:-}" in
  "api user")
    echo test-agent
    ;;
  "repo view")
    echo '{"name":"home"}'
    ;;
  "repo clone")
    target=${4:?clone target required}
    "$REAL_GIT" init -q "$target"
    "$REAL_GIT" -C "$target" remote add origin \
      "https://x-access-token:${GH_TOKEN:?}@github.com/test-agent/home.git"
    ;;
  "auth setup-git")
    ;;
  *)
    echo "unexpected gh invocation" >&2
    exit 2
    ;;
esac
SH

  cat > "$mock_bin/mise-internal" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'mise' >> "$MOCK_LOG"
printf '\t%s' "$@" >> "$MOCK_LOG"
printf '\n' >> "$MOCK_LOG"
if [ "${1:-} ${2:-} ${3:-}" = "tasks info agent:prepare" ]; then
  exit 1
fi
SH

  cat > "$mock_bin/secrets" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[ "${1:-} ${2:-}" = "get test-agent/email-password" ] || exit 2
printf 'fake-email-password\n'
SH

  cat > "$mock_bin/emails" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
cat >/dev/null
SH

  cat > "$mock_bin/shimmer" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[ "$#" -eq 2 ] || exit 2
[ "$1" = "gpg:setup" ] || exit 2
[ "$2" = "test-agent" ] || exit 2
SH

  chmod +x "$mock_bin"/*

  run env \
    PATH="$mock_bin:$PATH" \
    AGENT=test-agent \
    AGENT_HOME="$home" \
    GH_TOKEN="$token" \
    GITHUB_ENV="$github_env" \
    GH="$mock_bin/gh" \
    GIT="$real_git" \
    MISE="$mock_bin/mise-internal" \
    SECRETS="$mock_bin/secrets" \
    MOCK_LOG="$mock_log" \
    REAL_GIT="$real_git" \
    PI_AUTH_JSON= \
    "$real_mise" -C "$REPO_DIR" run -q ci:env

  [ "$status" -eq 0 ]
  [ "$("$real_git" -C "$home" remote get-url origin)" = \
    "https://github.com/test-agent/home.git" ]
  grep -Fq $'gh\trepo\tclone\ttest-agent/home\t' "$mock_log"
  [[ "$output" != *"$token"* ]]
  ! grep -R -Fq "$token" "$home/.git/config" "$mock_log" "$github_env"
}
