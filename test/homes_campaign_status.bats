#!/usr/bin/env bats

load test_helper

create_git_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.name "Test User"
  git -C "$dir" config user.email "test@example.com"
}

commit_all() {
  local dir="$1"
  git -C "$dir" add .
  git -C "$dir" -c commit.gpgsign=false commit -q -m "initial"
}

setup() {
  TEST_TMPDIR=$(mktemp -d)
  export TEST_TMPDIR

  STATE_DIR="$TEST_TMPDIR/state"
  ONE="$STATE_DIR/clones/one"
  TWO="$STATE_DIR/clones/two"
  ENC="$STATE_DIR/clones/encrypted"
  MISSING="$STATE_DIR/clones/missing"
  export STATE_DIR ONE TWO ENC MISSING

  mkdir -p "$STATE_DIR/clones"
  create_git_repo "$ONE"
  create_git_repo "$TWO"
  create_git_repo "$ENC"

  mkdir -p "$ONE/.mise/tasks/agent" "$ONE/notes" "$ONE/.modules" "$ONE/.git/hooks"
  cat > "$ONE/.mise/tasks/agent/prepare" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
BASH
  chmod +x "$ONE/.mise/tasks/agent/prepare"
  touch "$ONE/notes/.manifest"
  touch "$ONE/.modules/config"
  cat > "$ONE/.modules/manifest" <<'EOF'
fold	https://github.com/ricon-family/fold.git	0123456789abcdef0123456789abcdef01234567	main
den	https://github.com/ricon-family/den.git	abcdef0123456789abcdef0123456789abcdef01	main
EOF
  touch "$ONE/.git/hooks/pre-commit"
  chmod +x "$ONE/.git/hooks/pre-commit"
  commit_all "$ONE"

  echo "dirty" > "$TWO/untracked.txt"
  mkdir -p "$TWO/.modules"
  echo "not a readable manifest" > "$TWO/.modules/manifest"

  mkdir -p "$ENC/.modules"
  printf '\000GITCRYPT\000fake-encrypted-manifest' > "$ENC/.modules/manifest"
  commit_all "$ENC"

  cat > "$STATE_DIR/targets.tsv" <<TSV
repo	auth	clone	branch	base
owner/one	-	$ONE	campaign/test	main
owner/two	-	$TWO	campaign/test	main
owner/encrypted	-	$ENC	campaign/test	main
owner/missing	-	$MISSING	campaign/test	main
TSV
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

@test "homes:campaign:status reports generic clone details by default" {
  run fold_task homes:campaign:status --work-dir "$STATE_DIR"

  [ "$status" -eq 0 ]
  [[ "$output" == *$'Repo\tClone\tBranch\tDirty'* ]]
  [[ "$output" != *"Prepare"* ]]
  [[ "$output" == *$'owner/one\t'*$'\tmain\tclean'* ]]
  [[ "$output" == *$'owner/two\t'*$'\tmain\t2 changes'* ]]
  [[ "$output" == *$'owner/encrypted\t'*$'\tmain\tclean'* ]]
  [[ "$output" == *$'owner/missing\t'*$'\tmissing\tmissing'* ]]
}

@test "homes:campaign:status appends inline check columns" {
  run fold_task homes:campaign:status \
    --work-dir "$STATE_DIR" \
    --check 'Prepare=if [ -x .mise/tasks/agent/prepare ]; then printf yes; else printf missing; fi'

  [ "$status" -eq 0 ]
  [[ "$output" == *$'Repo\tClone\tBranch\tDirty\tPrepare'* ]]
  [[ "$output" == *$'owner/one\t'*$'\tmain\tclean\tyes'* ]]
  [[ "$output" == *$'owner/two\t'*$'\tmain\t2 changes\tmissing'* ]]
  [[ "$output" == *$'owner/missing\t'*$'\tmissing\tmissing\tclone-missing'* ]]
}

@test "homes:campaign:status appends check-file columns" {
  run fold_task homes:campaign:status \
    --work-dir "$STATE_DIR" \
    --checks "$REPO_DIR/checks/homes-agent-home.tsv"

  [ "$status" -eq 0 ]
  [[ "$output" == *$'Prepare\tNotes\tNotesHooks\tModulesConfig\tModulesManifest\tModule:fold\tModule:den'* ]]
  [[ "$output" == *$'owner/one\t'*$'\tmain\tclean\tyes\tyes\tpre:yes checkout:no\tyes\treadable\tyes\tyes'* ]]
  [[ "$output" == *$'owner/two\t'*$'\tmain\t2 changes\tmissing\tno\tn/a\tno\tunreadable\tunknown\tunknown'* ]]
  [[ "$output" == *$'owner/encrypted\t'*$'\tmain\tclean\tmissing\tno\tn/a\tno\tencrypted\tencrypted\tencrypted'* ]]
}

@test "homes:campaign:status shows failing check results" {
  run fold_task homes:campaign:status \
    --work-dir "$STATE_DIR" \
    --repo owner/one \
    --check 'Boom=echo broken; exit 7'

  [ "$status" -eq 0 ]
  [[ "$output" == *$'owner/one\t'*$'\tfail:7 broken'* ]]
}

@test "homes:campaign:status filters by repo" {
  run fold_task homes:campaign:status --work-dir "$STATE_DIR" --repo owner/two

  [ "$status" -eq 0 ]
  [[ "$output" != *"owner/one"* ]]
  [[ "$output" == *"owner/two"* ]]
  [[ "$output" != *"owner/missing"* ]]
}

@test "homes:campaign:status fails when no target matches" {
  run fold_task homes:campaign:status --work-dir "$STATE_DIR" --repo owner/nope

  [ "$status" -ne 0 ]
  [[ "$output" == *"no campaign targets matched"* ]]
}

@test "homes:campaign:status fails before init" {
  run fold_task homes:campaign:status --work-dir "$TEST_TMPDIR/absent"

  [ "$status" -ne 0 ]
  [[ "$output" == *"targets file not found"* ]]
}
