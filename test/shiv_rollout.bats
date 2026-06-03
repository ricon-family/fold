#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load test_helper

setup() {
  export GIT_AUTHOR_NAME="k7r2"
  export GIT_AUTHOR_EMAIL="k7r2@ricon.family"
  export MOCK_GIT_REMOTE_ROOT="$BATS_TEST_TMPDIR/remotes"
  export MOCK_GIT_LOG="$BATS_TEST_TMPDIR/git.log"
  mkdir -p "$MOCK_GIT_REMOTE_ROOT"
  : > "$MOCK_GIT_LOG"
  write_rollout_mock_git
  write_rollout_mock_secrets
}

write_rollout_mock_git() {
  local path="$BATS_TEST_TMPDIR/git"
  local real_git
  real_git=$(command -v git)

  cat > "$path" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'GH_TOKEN=%s ARGS=' "${GH_TOKEN:-ambient}" >> "${MOCK_GIT_LOG:?}"
printf '%q ' "$@" >> "$MOCK_GIT_LOG"
printf '\n' >> "$MOCK_GIT_LOG"

rewritten=()
for arg in "$@"; do
  case "$arg" in
    https://github.com/*.git)
      repo="${arg#https://github.com/}"
      repo="${repo%.git}"
      rewritten+=("$MOCK_GIT_REMOTE_ROOT/$repo.git")
      ;;
    *)
      rewritten+=("$arg")
      ;;
  esac
done

exec "$REAL_GIT" "${rewritten[@]}"
SH
  chmod +x "$path"
  export REAL_GIT="$real_git"
  export GIT="$path"
}

write_rollout_mock_secrets() {
  local path="$BATS_TEST_TMPDIR/secrets"
  cat > "$path" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" != "get" ]; then
  echo "unexpected secrets command: $*" >&2
  exit 2
fi
case "${2:-}" in
  baby-joel/github-pat) echo "token-baby-joel" ;;
  quick/github-username) echo "quick-ricon" ;;
  quick/github-pat) echo "token-quick" ;;
  zeke/github-pat) echo "token-zeke" ;;
  *) echo "missing secret: ${2:-}" >&2; exit 1 ;;
esac
SH
  chmod +x "$path"
  export SECRETS="$path"
}

create_remote_repo() {
  local repo="$1" content="$2"
  local work="$BATS_TEST_TMPDIR/work-${repo//\//-}"
  local bare="$MOCK_GIT_REMOTE_ROOT/$repo.git"

  mkdir -p "$(dirname "$bare")"
  git init -q -b main "$work"
  printf '%s\n' "$content" > "$work/mise.toml"
  git -C "$work" add mise.toml
  git -C "$work" \
    -c user.name="fixture" \
    -c user.email="fixture@example.test" \
    -c commit.gpgsign=false \
    commit -q -m "initial"
  git clone -q --bare "$work" "$bare"
}

show_remote_file() {
  local repo="$1" ref="$2" file="$3"
  git --git-dir="$MOCK_GIT_REMOTE_ROOT/$repo.git" show "$ref:$file"
}

@test "shiv:rollout dry-run updates existing pins without pushing" {
  create_remote_repo "baby-joel/home" '[settings]
quiet = true

[tools]
"shiv:notes" = "0.8"
"shiv:emails" = "0.5"
'
  run fold_task shiv:rollout emails 0.6 \
    --repo baby-joel/home:baby-joel \
    --branch rollout/emails-0.6 \
    --work-dir "$BATS_TEST_TMPDIR/clones" \
    --no-gpg-sign

  [ "$status" -eq 0 ]
  [[ "$output" == *"dependency: updated"* ]]
  [[ "$output" == *"dry-run: would commit and push rollout/emails-0.6"* ]]
  grep -q 'GH_TOKEN=token-baby-joel ARGS=.* clone .*baby-joel/home.git' "$MOCK_GIT_LOG"
  run git --git-dir="$MOCK_GIT_REMOTE_ROOT/baby-joel/home.git" show-ref --verify refs/heads/rollout/emails-0.6
  [ "$status" -ne 0 ]
}

@test "shiv:rollout --home adds missing dependency and pushes with target token" {
  create_remote_repo "quick-ricon/home" '[settings]
quiet = true

[tools]
"shiv:notes" = "0.8"
jq = "1.8.1"
'

  run fold_task shiv:rollout emails 0.6 \
    --home quick \
    --branch rollout/emails-0.6 \
    --message "deps: add emails 0.6" \
    --work-dir "$BATS_TEST_TMPDIR/clones" \
    --add-missing \
    --no-gpg-sign \
    --yes

  [ "$status" -eq 0 ]
  [[ "$output" == *"dependency: added"* ]]
  [[ "$output" == *"pushed: rollout/emails-0.6"* ]]
  grep -q 'GH_TOKEN=token-quick ARGS=.* clone .*quick-ricon/home.git' "$MOCK_GIT_LOG"
  grep -q 'GH_TOKEN=token-quick ARGS=.* push origin HEAD:refs/heads/rollout/emails-0.6' "$MOCK_GIT_LOG"
  [[ "$(show_remote_file "quick-ricon/home" "refs/heads/rollout/emails-0.6" mise.toml)" == *'"shiv:emails" = "0.6"'* ]]
  author=$(git --git-dir="$MOCK_GIT_REMOTE_ROOT/quick-ricon/home.git" log -1 --format='%an <%ae>' refs/heads/rollout/emails-0.6)
  [ "$author" = "k7r2 <k7r2@ricon.family>" ]
}

@test "shiv:rollout accepts plan rows from stdin" {
  create_remote_repo "zeke/home" '[settings]
quiet = true

[tools]
"shiv:notes" = "0.8"
'
  run bash -c 'printf "zeke/home\tzeke\n" | fold_task shiv:rollout emails 0.6 --plan - --branch rollout/emails-0.6 --work-dir "$BATS_TEST_TMPDIR/clones" --no-gpg-sign'

  [ "$status" -eq 0 ]
  [[ "$output" == *"dependency: missing"* ]]
  run git --git-dir="$MOCK_GIT_REMOTE_ROOT/zeke/home.git" show-ref --verify refs/heads/rollout/emails-0.6
  [ "$status" -ne 0 ]
}
