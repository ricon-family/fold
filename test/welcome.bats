#!/usr/bin/env bats

load test_helper

setup() {
  MODULE_DIR="$REPO_DIR/modules/welcome-observational-$BATS_TEST_NUMBER-$$"
  REMOTE_DIR="$BATS_TEST_TMPDIR/welcome-module.git"
  WRITER_DIR="$BATS_TEST_TMPDIR/welcome-writer"

  mkdir -p "$REPO_DIR/modules"
  git init -q --bare "$REMOTE_DIR"
  git -C "$REMOTE_DIR" symbolic-ref HEAD refs/heads/main

  git init -q -b main "$MODULE_DIR"
  git -C "$MODULE_DIR" config user.name fixture
  git -C "$MODULE_DIR" config user.email fixture@example.test
  git -C "$MODULE_DIR" config commit.gpgsign false
  mkdir -p "$MODULE_DIR/notes"
  printf 'module fixture\n' > "$MODULE_DIR/README.md"
  : > "$MODULE_DIR/notes/.manifest"
  git -C "$MODULE_DIR" add README.md notes/.manifest
  git -C "$MODULE_DIR" commit -q -m initial
  git -C "$MODULE_DIR" remote add origin "$REMOTE_DIR"
  git -C "$MODULE_DIR" push -q -u origin main

  git clone -q "$REMOTE_DIR" "$WRITER_DIR"
  git -C "$WRITER_DIR" config user.name fixture
  git -C "$WRITER_DIR" config user.email fixture@example.test
  git -C "$WRITER_DIR" config commit.gpgsign false
  printf 'remote update\n' >> "$WRITER_DIR/README.md"
  git -C "$WRITER_DIR" add README.md
  git -C "$WRITER_DIR" commit -q -m update
  git -C "$WRITER_DIR" push -q origin main
}

teardown() {
  rm -rf "$MODULE_DIR"
}

@test "welcome reports nested module drift without fetching or installing hooks" {
  recorded_origin=$(git -C "$MODULE_DIR" rev-parse refs/remotes/origin/main)
  remote_main=$(git --git-dir="$REMOTE_DIR" rev-parse refs/heads/main)
  [ "$recorded_origin" != "$remote_main" ]
  [ ! -e "$MODULE_DIR/.git/hooks/pre-commit" ]

  run fold_task welcome --local
  [ "$status" -eq 0 ]

  [ "$(git -C "$MODULE_DIR" rev-parse refs/remotes/origin/main)" = "$recorded_origin" ]
  [ ! -e "$MODULE_DIR/.git/hooks/pre-commit" ]
  [[ "$output" == *"at recorded origin/main"* ]]
  [[ "$output" == *"missing → notes install-hooks"* ]]
}

@test "local welcome invokes no Notes chat or GitHub capability" {
  CAPABILITY_LOG="$BATS_TEST_TMPDIR/capabilities.log"
  export CAPABILITY_LOG
  : > "$CAPABILITY_LOG"

  notes() { printf 'notes %s\n' "$*" >> "$CAPABILITY_LOG"; return 97; }
  chat() { printf 'chat %s\n' "$*" >> "$CAPABILITY_LOG"; return 98; }
  gh() { printf 'gh %s\n' "$*" >> "$CAPABILITY_LOG"; return 99; }
  export -f notes chat gh

  run fold_task welcome --local
  [ "$status" -eq 0 ]
  [ ! -s "$CAPABILITY_LOG" ]
  [[ "$output" == *"Recent Fold note changes"* ]]
  [[ "$output" == *"edits checked by: notes status"* ]]
}

@test "resident welcome uses explicit bounded Fold chat and verified KKL GitHub attention" {
  CAPABILITY_LOG="$BATS_TEST_TMPDIR/capabilities.log"
  export CAPABILITY_LOG
  : > "$CAPABILITY_LOG"
  export AGENT_NAME=junior

  notes() {
    printf 'notes %s\n' "$*" >> "$CAPABILITY_LOG"
    return 97
  }
  chat() {
    printf 'chat %s\n' "$*" >> "$CAPABILITY_LOG"
    cat <<'JSON'
[
  {"sender":"one","timestamp":"t1","preview":"first"},
  {"sender":"two","timestamp":"t2","preview":"second"},
  {"sender":"three","timestamp":"t3","preview":"third"},
  {"sender":"four","timestamp":"t4","preview":"fourth"},
  {"sender":"five","timestamp":"t5","preview":"fifth"},
  {"sender":"six","timestamp":"t6","preview":"sixth"}
]
JSON
  }
  gh() {
    printf 'gh %s\n' "$*" >> "$CAPABILITY_LOG"
    if [ "${1:-}" = api ] && [ "${2:-}" = graphql ]; then
      echo junior-ricon
    elif [ "${1:-}" = search ] && [ "${2:-}" = prs ] && [[ " $* " == *" --review-requested "* ]]; then
      printf '%s\n' '[{"number":164,"title":"Shared orientation","url":"https://example.test/164","repository":{"nameWithOwner":"ricon-family/fold"},"updatedAt":"now"}]'
    elif [ "${1:-}" = search ] && [ "${2:-}" = prs ]; then
      cat <<'JSON'
[
  {"number":797,"title":"Hosted cache","url":"https://example.test/797","repository":{"nameWithOwner":"KnickKnackLabs/shimmer"},"updatedAt":"now"},
  {"number":2,"title":"authored two","url":"https://example.test/2","repository":{"nameWithOwner":"KnickKnackLabs/two"},"updatedAt":"now"},
  {"number":3,"title":"authored three","url":"https://example.test/3","repository":{"nameWithOwner":"KnickKnackLabs/three"},"updatedAt":"now"},
  {"number":4,"title":"authored four","url":"https://example.test/4","repository":{"nameWithOwner":"KnickKnackLabs/four"},"updatedAt":"now"},
  {"number":5,"title":"authored five","url":"https://example.test/5","repository":{"nameWithOwner":"KnickKnackLabs/five"},"updatedAt":"now"},
  {"number":6,"title":"sixth github item","url":"https://example.test/6","repository":{"nameWithOwner":"KnickKnackLabs/six"},"updatedAt":"now"}
]
JSON
    elif [ "${1:-}" = search ] && [ "${2:-}" = issues ]; then
      printf '%s\n' '[{"number":152,"title":"Fail closed","url":"https://example.test/152","repository":{"nameWithOwner":"KnickKnackLabs/notes"},"updatedAt":"now"}]'
    else
      return 96
    fi
  }
  export -f notes chat gh

  run fold_task welcome
  [ "$status" -eq 0 ]
  ! grep -q '^notes ' "$CAPABILITY_LOG"
  grep -q '^chat read fold --as junior --peek --all --last 5 --json$' "$CAPABILITY_LOG"
  [ "$(grep '^gh ' "$CAPABILITY_LOG" | head -n 1)" = "gh api graphql -f query=query { viewer { login } } --jq .data.viewer.login" ]
  [ "$(grep -c '^gh search ' "$CAPABILITY_LOG")" -eq 3 ]
  [ "$(grep -c -- '--owner KnickKnackLabs --owner ricon-family' "$CAPABILITY_LOG")" -eq 3 ]
  [[ "$output" == *"Resident: junior"* ]]
  [[ "$output" == *"Verified account: junior-ricon"* ]]
  [[ "$output" == *"Shared orientation"* ]]
  [[ "$output" == *"fifth"* ]]
  [[ "$output" != *"sixth"* ]]
  [[ "$output" != *"sixth github item"* ]]
}

@test "visitor welcome never impersonates a resident" {
  CAPABILITY_LOG="$BATS_TEST_TMPDIR/capabilities.log"
  export CAPABILITY_LOG
  : > "$CAPABILITY_LOG"
  export AGENT_NAME=rikonor
  export CHAT_IDENTITY=rikonor
  export GIT_AUTHOR_NAME=rikonor

  chat() { printf 'chat %s\n' "$*" >> "$CAPABILITY_LOG"; return 98; }
  gh() {
    printf 'gh %s\n' "$*" >> "$CAPABILITY_LOG"
    if [ "${1:-}" = api ]; then
      echo rikonor
    else
      echo '[]'
    fi
  }
  export -f chat gh

  run fold_task welcome
  [ "$status" -eq 0 ]
  ! grep -q '^chat ' "$CAPABILITY_LOG"
  [[ "$output" == *"Visitor: rikonor"* ]]
  [[ "$output" == *"Verified account: rikonor"* ]]
}

@test "live capability failure preserves the local dashboard" {
  export AGENT_NAME=junior
  chat() { return 42; }
  gh() {
    if [ "${1:-}" = api ]; then echo rikonor; else return 43; fi
  }
  export -f chat gh

  run fold_task welcome
  [ "$status" -eq 0 ]
  [[ "$output" == *"Recent Fold note changes"* ]]
  [[ "$output" == *"Fold repository"* ]]
  [[ "$output" == *"Fold chat unavailable"* ]]
  [[ "$output" == *"does not match resident junior-ricon"* ]]
}

@test "recent note changes map encrypted ids and remain bounded" {
  fixture="$BATS_TEST_TMPDIR/recent-notes"
  git init -q -b main "$fixture"
  git -C "$fixture" config user.name fixture
  git -C "$fixture" config user.email fixture@example.test
  git -C "$fixture" config commit.gpgsign false
  mkdir -p "$fixture/notes"
  : > "$fixture/notes/.manifest"

  for n in 1 2 3 4 5 6; do
    id="deadbee$n"
    name="note-$n.md"
    printf '%s\t%s\n' "$id" "$name" >> "$fixture/notes/.manifest"
    printf 'note %s\n' "$n" > "$fixture/notes/$id"
  done
  git -C "$fixture" add notes
  git -C "$fixture" commit -q -m 'add mapped notes'

  source "$REPO_DIR/.mise/lib/welcome.sh"
  run fold_welcome_recent_note_changes "$fixture" 5
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 5 ]
  [[ "$output" == *"note-1.md"* ]]
  [[ "$output" != *"deadbee"* ]]
}
