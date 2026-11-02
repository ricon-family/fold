#!/usr/bin/env bats

load test_helper

setup() {
  TEST_TMPDIR=$(mktemp -d)
  export TEST_TMPDIR
  unset GH_TOKEN GITHUB_TOKEN

  MOCK_BIN="$TEST_TMPDIR/bin"
  mkdir -p "$MOCK_BIN"

  GIT_LOG="$TEST_TMPDIR/git.log"
  SECRET_LOG="$TEST_TMPDIR/secrets.log"
  export GIT_LOG SECRET_LOG

  cat > "$MOCK_BIN/git" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail

printf 'GH_TOKEN=%s' "${GH_TOKEN:+set}" >> "$GIT_LOG"
printf ' args:' >> "$GIT_LOG"
for arg in "$@"; do
  printf ' %s' "$arg" >> "$GIT_LOG"
done
printf '\n' >> "$GIT_LOG"

while [ "$#" -gt 0 ]; do
  case "$1" in
    -c)
      shift 2
      ;;
    *)
      break
      ;;
  esac
done

if [ "${1:-}" = "clone" ]; then
  dest=""
  for arg in "$@"; do
    dest="$arg"
  done
  mkdir -p "$dest/.git"
  printf 'cloned\n' > "$dest/.git/mock"
  exit 0
fi

if [ "${1:-}" = "-C" ]; then
  dir="$2"
  shift 2
  if [ "${1:-}" = "checkout" ] && [ "${2:-}" = "-B" ]; then
    printf '%s\n' "$3" > "$dir/.git/branch"
    exit 0
  fi
fi

echo "unexpected git invocation: $*" >&2
exit 2
BASH
  chmod +x "$MOCK_BIN/git"

  cat > "$MOCK_BIN/secrets" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
printf 'args:' >> "$SECRET_LOG"
for arg in "$@"; do
  printf ' %s' "$arg" >> "$SECRET_LOG"
done
printf '\n' >> "$SECRET_LOG"

if [ "${1:-}" = "get" ] && [ "${2:-}" = "c0da/github-pat" ]; then
  printf 'test-token\n'
  exit 0
fi

echo "missing secret: $*" >&2
exit 1
BASH
  chmod +x "$MOCK_BIN/secrets"

  export GIT="$MOCK_BIN/git"
  export SECRETS="$MOCK_BIN/secrets"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

@test "homes:campaign:init clones repos and records targets" {
  run fold_task homes:campaign:init \
    --work-dir "$TEST_TMPDIR/state" \
    --branch c0da/agent-prepare-module-hooks \
    --repo c0da-ricon/home:c0da \
    --repo KnickKnackLabs/emails:-

  [ "$status" -eq 0 ]
  [ -d "$TEST_TMPDIR/state/clones/c0da-ricon__home/.git" ]
  [ -d "$TEST_TMPDIR/state/clones/KnickKnackLabs__emails/.git" ]
  [ "$(cat "$TEST_TMPDIR/state/clones/c0da-ricon__home/.git/branch")" = "c0da/agent-prepare-module-hooks" ]

  grep -F $'repo\tauth\tclone\tbranch\tbase' "$TEST_TMPDIR/state/targets.tsv"
  grep -F $'c0da-ricon/home\tc0da\t' "$TEST_TMPDIR/state/targets.tsv"
  grep -F $'KnickKnackLabs/emails\t-\t' "$TEST_TMPDIR/state/targets.tsv"
  grep -F 'Campaign initialized:' <<< "$output"
}

@test "homes:campaign:init uses named auth only when requested" {
  run fold_task homes:campaign:init \
    --work-dir "$TEST_TMPDIR/state" \
    --branch c0da/example \
    --repo c0da-ricon/home:c0da \
    --repo KnickKnackLabs/template

  [ "$status" -eq 0 ]
  grep -F 'args: get c0da/github-pat' "$SECRET_LOG"
  [ "$(grep -c 'GH_TOKEN=set' "$GIT_LOG")" -eq 2 ]
  [ "$(grep -c 'GH_TOKEN=' "$GIT_LOG")" -eq 4 ]
}

@test "homes:campaign:init refuses missing repo targets" {
  run fold_task homes:campaign:init \
    --work-dir "$TEST_TMPDIR/state" \
    --branch c0da/example

  [ "$status" -ne 0 ]
  [[ "$output" == *"provide at least one --repo target"* ]]
}

@test "homes:campaign:init refuses existing work dir without force" {
  mkdir -p "$TEST_TMPDIR/state"

  run fold_task homes:campaign:init \
    --work-dir "$TEST_TMPDIR/state" \
    --branch c0da/example \
    --repo KnickKnackLabs/template

  [ "$status" -ne 0 ]
  [[ "$output" == *"work dir already exists"* ]]
}
