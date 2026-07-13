#!/usr/bin/env bats

load test_helper

make_repo() {
  local name="$1" remote seed clone
  remote="$TEST_TMPDIR/$name.git"
  seed="$TEST_TMPDIR/$name-seed"
  clone="$STATE_DIR/clones/$name"

  git init -q --bare "$remote"
  git init -q -b main "$seed"
  git -C "$seed" config user.name "Test User"
  git -C "$seed" config user.email "test@example.com"
  printf 'base\n' > "$seed/file.txt"
  git -C "$seed" add file.txt
  git -C "$seed" -c commit.gpgsign=false commit -q -m base
  git -C "$seed" remote add origin "$remote"
  git -C "$seed" push -q origin main

  git clone -q "$remote" "$clone"
  git -C "$clone" config user.name "Test User"
  git -C "$clone" config user.email "test@example.com"
  git -C "$clone" checkout -q -B campaign/test origin/main
  printf '%s campaign\n' "$name" >> "$clone/file.txt"
  git -C "$clone" -c commit.gpgsign=false commit -q -am "campaign change"
  git -C "$clone" push -q origin campaign/test

  printf '%s\n' "$clone"
}

make_diverged_repo() {
  local name="$1" clone
  clone=$(make_repo "$name")

  git -C "$clone" checkout -q main
  printf 'main-only\n' >> "$clone/file.txt"
  git -C "$clone" -c commit.gpgsign=false commit -q -am "main-only change"
  git -C "$clone" push -q origin main
  git -C "$clone" checkout -q campaign/test

  printf '%s\n' "$clone"
}

setup() {
  TEST_TMPDIR=$(mktemp -d)
  export TEST_TMPDIR

  STATE_DIR="$TEST_TMPDIR/state"
  mkdir -p "$STATE_DIR/clones"
  export STATE_DIR

  MOCK_SECRETS="$TEST_TMPDIR/secrets"
  cat > "$MOCK_SECRETS" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
printf 'missing secret: %s\n' "${2:-}" >&2
exit 1
BASH
  chmod +x "$MOCK_SECRETS"
  export SECRETS="$MOCK_SECRETS"

  ONE=$(make_repo one)
  TWO=$(make_repo two)
  DIVERGED=$(make_diverged_repo diverged)
  export ONE TWO DIVERGED

  cat > "$STATE_DIR/targets.tsv" <<TSV
repo	auth	clone	branch	base
owner/one	-	$ONE	campaign/test	main
owner/two	-	$TWO	campaign/test	main
owner/diverged	-	$DIVERGED	campaign/test	main
owner/auth-fail	missing	$ONE	campaign/test	main
owner/fetch-fail	-	$TWO	campaign/test	main
TSV
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

@test "homes:campaign:merge dry-run reports fast-forwardable targets without pushing" {
  run fold_task homes:campaign:merge \
    --work-dir "$STATE_DIR" \
    --repo owner/one \
    --dry-run

  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY owner/one"* ]]

  main_sha=$(git -C "$ONE" rev-parse origin/main)
  campaign_sha=$(git -C "$ONE" rev-parse origin/campaign/test)
  [ "$main_sha" != "$campaign_sha" ]
}

@test "homes:campaign:merge fast-forwards target branch" {
  run fold_task homes:campaign:merge \
    --work-dir "$STATE_DIR" \
    --repo owner/one

  [ "$status" -eq 0 ]
  [[ "$output" == *"MER owner/one"* ]]

  git -C "$ONE" fetch -q origin main
  main_sha=$(git -C "$ONE" rev-parse origin/main)
  campaign_sha=$(git -C "$ONE" rev-parse origin/campaign/test)
  [ "$main_sha" = "$campaign_sha" ]
}

@test "homes:campaign:merge refuses non-fast-forward target" {
  run fold_task homes:campaign:merge \
    --work-dir "$STATE_DIR" \
    --repo owner/diverged

  [ "$status" -ne 0 ]
  [[ "$output" == *"DIV owner/diverged"* ]]
}

@test "homes:campaign:merge keep-going checks remaining targets after a failure" {
  run fold_task homes:campaign:merge \
    --work-dir "$STATE_DIR" \
    --repo owner/diverged \
    --repo owner/two \
    --keep-going \
    --dry-run

  [ "$status" -ne 0 ]
  [[ "$output" == *"DIV owner/diverged"* ]]
  [[ "$output" == *"DRY owner/two"* ]]
}

@test "homes:campaign:merge fails closed on auth errors and keeps going" {
  run fold_task homes:campaign:merge \
    --work-dir "$STATE_DIR" \
    --repo owner/auth-fail \
    --repo owner/two \
    --keep-going \
    --dry-run

  [ "$status" -ne 0 ]
  [[ "$output" == *"could not read missing/github-pat"* ]]
  [[ "$output" != *"OK  owner/auth-fail"* ]]
  [[ "$output" != *"DRY owner/auth-fail"* ]]
  [[ "$output" != *"MER owner/auth-fail"* ]]
  [[ "$output" == *"DRY owner/two"* ]]
}

@test "homes:campaign:merge fails closed on fetch errors and keeps going" {
  rm -rf "$TEST_TMPDIR/two.git"

  run fold_task homes:campaign:merge \
    --work-dir "$STATE_DIR" \
    --repo owner/fetch-fail \
    --repo owner/one \
    --keep-going \
    --dry-run

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: could not fetch owner/fetch-fail main"* ]]
  [[ "$output" != *"OK  owner/fetch-fail"* ]]
  [[ "$output" != *"DRY owner/fetch-fail"* ]]
  [[ "$output" != *"MER owner/fetch-fail"* ]]
  [[ "$output" == *"DRY owner/one"* ]]
}

@test "homes:campaign:merge fails closed when the remote rejects a push" {
  cat > "$TEST_TMPDIR/two.git/hooks/pre-receive" <<'BASH'
#!/usr/bin/env bash
echo "push rejected intentionally" >&2
exit 1
BASH
  chmod +x "$TEST_TMPDIR/two.git/hooks/pre-receive"

  run fold_task homes:campaign:merge \
    --work-dir "$STATE_DIR" \
    --repo owner/two

  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: could not push owner/two main"* ]]
  [[ "$output" != *"MER owner/two"* ]]
}

@test "homes:campaign:merge fails before init" {
  run fold_task homes:campaign:merge --work-dir "$TEST_TMPDIR/absent"

  [ "$status" -ne 0 ]
  [[ "$output" == *"targets file not found"* ]]
}
