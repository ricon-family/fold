#!/usr/bin/env bats

load test_helper

setup() {
  TMPBIN="$BATS_TEST_TMPDIR/bin"
  AUTH_SOURCE="$BATS_TEST_TMPDIR/auth.json"
  GH_LOG="$BATS_TEST_TMPDIR/gh.log"
  mkdir -p "$TMPBIN"
  export TMPBIN AUTH_SOURCE GH_LOG

  cat > "$AUTH_SOURCE" <<'JSON'
{"openai-codex":{"token":"do-not-print"}}
JSON

  cat > "$TMPBIN/secrets" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "get" ]; then
  case "${2:-}" in
    alpha/github-pat) printf 'token-alpha\n' ;;
    beta-bot/github-pat) printf 'token-beta\n' ;;
    *) echo "missing secret: ${2:-}" >&2; exit 1 ;;
  esac
  exit 0
fi
echo "unexpected secrets invocation: $*" >&2
exit 2
SH
  chmod +x "$TMPBIN/secrets"
  export SECRETS="$TMPBIN/secrets"

  cat > "$TMPBIN/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'args:' >> "${GH_LOG:?}"
for arg in "$@"; do printf ' %s' "$arg" >> "$GH_LOG"; done
printf '\n' >> "$GH_LOG"

if [ "${1:-}" = "secret" ] && [ "${2:-}" = "list" ]; then
  [ -n "${GH_TOKEN:-}" ] || { echo 'GH_TOKEN missing' >&2; exit 3; }
  repo=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --repo)
        repo="${2:-}"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done

  case "$repo" in
    owner/full)
      printf '%s\n' ALPHA_GITHUB_PAT ALPHA_GPG_PRIVATE_KEY ALPHA_EMAIL_PASSWORD PI_AUTH_JSON
      exit 0
      ;;
    owner/partial)
      printf '%s\n' BETA_BOT_GITHUB_PAT BETA_BOT_EMAIL_PASSWORD
      exit 0
      ;;
    owner/pi)
      printf '%s\n' PI_AUTH_JSON
      exit 0
      ;;
    owner/error)
      echo 'bad credentials: ghp_should_be_redacted' >&2
      exit 42
      ;;
  esac
fi

echo "unexpected gh invocation: $*" >&2
exit 2
SH
  chmod +x "$TMPBIN/gh"
  export GH="$TMPBIN/gh"
}

@test "homes:ci:secrets:status reports required agent and PI secrets without values" {
  run fold_task homes:ci:secrets:status \
    --repo owner/full:alpha \
    --repo owner/partial:beta-bot

  [ "$status" -eq 0 ]
  [[ "$output" == *$'Repo\tAgent\tSecret\tStatus\tDetail'* ]]
  [[ "$output" == *$'owner/full\talpha\tALPHA_GITHUB_PAT\tpresent'* ]]
  [[ "$output" == *$'owner/full\talpha\tALPHA_GPG_PRIVATE_KEY\tpresent'* ]]
  [[ "$output" == *$'owner/full\talpha\tALPHA_EMAIL_PASSWORD\tpresent'* ]]
  [[ "$output" == *$'owner/full\talpha\tPI_AUTH_JSON\tpresent'* ]]
  [[ "$output" == *$'owner/partial\tbeta-bot\tBETA_BOT_GITHUB_PAT\tpresent'* ]]
  [[ "$output" == *$'owner/partial\tbeta-bot\tBETA_BOT_GPG_PRIVATE_KEY\tmissing'* ]]
  [[ "$output" == *$'owner/partial\tbeta-bot\tPI_AUTH_JSON\tmissing'* ]]
  [[ "$output" != *"do-not-print"* ]]
  [[ "$output" != *"token-alpha"* ]]
  [[ "$output" != *"token-beta"* ]]
}

@test "homes:ci:secrets:status --check fails on missing secrets" {
  run fold_task homes:ci:secrets:status --repo owner/partial:beta-bot --check

  [ "$status" -eq 1 ]
  [[ "$output" == *$'BETA_BOT_GPG_PRIVATE_KEY\tmissing'* ]]
}

@test "homes:ci:secrets:status redacts gh errors" {
  run fold_task homes:ci:secrets:status --repo owner/error:alpha

  [ "$status" -eq 0 ]
  [[ "$output" == *$'owner/error\talpha\t-\terror'* ]]
  [[ "$output" == *"[REDACTED_GITHUB_TOKEN]"* ]]
  [[ "$output" != *"ghp_should_be_redacted"* ]]
}

@test "homes:ci:secrets:status requires explicit agent in repo targets" {
  run fold_task homes:ci:secrets:status --repo owner/full

  [ "$status" -ne 0 ]
  [[ "$output" == *"repo target must include :agent"* ]]
}

@test "homes:ci:pi-auth:status reports source validity and PI secret presence" {
  run fold_task homes:ci:pi-auth:status \
    --source "$AUTH_SOURCE" \
    --repo owner/full:alpha \
    --repo owner/partial:beta-bot

  [ "$status" -eq 0 ]
  [[ "$output" == *$'Source\tStatus\tDetail'* ]]
  [[ "$output" == *$''"$AUTH_SOURCE"$'\tpresent\tvalid JSON object'* ]]
  [[ "$output" == *$'owner/full\talpha\tPI_AUTH_JSON\tpresent'* ]]
  [[ "$output" == *$'owner/partial\tbeta-bot\tPI_AUTH_JSON\tmissing'* ]]
  [[ "$output" != *"do-not-print"* ]]
  [[ "$output" != *"token-alpha"* ]]
  [[ "$output" != *"token-beta"* ]]
}

@test "homes:ci:pi-auth:status --check fails on invalid source or missing repo secret" {
  empty_source="$BATS_TEST_TMPDIR/empty-auth.json"
  : > "$empty_source"

  run fold_task homes:ci:pi-auth:status \
    --source "$empty_source" \
    --repo owner/partial:beta-bot \
    --check

  [ "$status" -eq 1 ]
  [[ "$output" == *$'Source\tStatus\tDetail'* ]]
  [[ "$output" == *$''"$empty_source"$'\tinvalid\tsource file is empty'* ]]
  [[ "$output" == *$'owner/partial\tbeta-bot\tPI_AUTH_JSON\tmissing'* ]]
}
