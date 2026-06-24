#!/usr/bin/env bats

load test_helper

setup() {
  TEST_TMPDIR=$(mktemp -d)
  export TEST_TMPDIR
  MOCK_NOTES="$TEST_TMPDIR/notes"
  cat > "$MOCK_NOTES" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "status" ] && [ "${2:-}" = "--json" ]; then
  case "$PWD" in
    *locked*) printf '{"encryption":{"status":"locked"},"obfuscation":{"status":"unknown"}}\n' ;;
    *) printf '{"encryption":{"status":"unlocked"},"obfuscation":{"status":"deobfuscated"}}\n' ;;
  esac
  exit 0
fi
echo "unexpected notes command: $*" >&2
exit 2
SH
  chmod +x "$MOCK_NOTES"
  export NOTES="$MOCK_NOTES"
}

teardown() {
  rm -rf "$TEST_TMPDIR"
}

make_git_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q -b main
}

add_prepare_task() {
  local dir="$1"
  mkdir -p "$dir/.mise/tasks/agent"
  cat > "$dir/.mise/tasks/agent/prepare" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
SH
  chmod +x "$dir/.mise/tasks/agent/prepare"
}

add_notes_ready() {
  local dir="$1"
  mkdir -p "$dir/notes" "$dir/.git/hooks"
  touch "$dir/notes/.manifest" "$dir/.git/hooks/pre-commit" "$dir/.git/hooks/post-checkout"
}

add_modules_manifest() {
  local dir="$1"
  mkdir -p "$dir/.modules"
  touch "$dir/.modules/config"
  cat > "$dir/.modules/manifest" <<'EOF'
den	https://github.com/ricon-family/den.git	0123456789abcdef0123456789abcdef01234567	main
fold	https://github.com/ricon-family/fold.git	abcdef0123456789abcdef0123456789abcdef01	main
EOF
}

add_module_clone() {
  local home="$1" module="$2"
  local dir="$home/modules/$module"
  make_git_repo "$dir"
  add_notes_ready "$dir"
}

@test "agent:smoke passes for a prepared home with required modules" {
  home="$TEST_TMPDIR/home"
  make_git_repo "$home"
  add_prepare_task "$home"
  add_notes_ready "$home"
  add_modules_manifest "$home"
  add_module_clone "$home" den
  add_module_clone "$home" fold

  run env AGENT_PREPARE_MODULES="den fold" bash -c 'fold_task agent:smoke --home "$1"' _ "$home"

  [ "$status" -eq 0 ]
  [[ "$output" == *$'home notes\tOK\tunlocked/deobfuscated'* ]]
  [[ "$output" == *$'required modules\tOK\tden fold'* ]]
  [[ "$output" == *$'module:fold notes\tOK\tunlocked/deobfuscated'* ]]
}

@test "agent:smoke fails when notes-managed home is locked" {
  home="$TEST_TMPDIR/locked-home"
  make_git_repo "$home"
  add_prepare_task "$home"
  add_notes_ready "$home"

  run fold_task agent:smoke --home "$home"

  [ "$status" -ne 0 ]
  [[ "$output" == *$'home notes\tFAIL\tlocked/unknown'* ]]
}

@test "agent:smoke fails when required modules are missing" {
  home="$TEST_TMPDIR/home"
  make_git_repo "$home"
  add_prepare_task "$home"
  add_modules_manifest "$home"
  add_module_clone "$home" den

  run env AGENT_PREPARE_MODULES="den fold" bash -c 'fold_task agent:smoke --home "$1"' _ "$home"

  [ "$status" -ne 0 ]
  [[ "$output" == *$'required modules\tFAIL\tmissing: fold'* ]]
}

@test "agent:smoke fails when notes hooks are missing" {
  home="$TEST_TMPDIR/home"
  make_git_repo "$home"
  add_prepare_task "$home"
  mkdir -p "$home/notes"
  touch "$home/notes/.manifest"

  run fold_task agent:smoke --home "$home"

  [ "$status" -ne 0 ]
  [[ "$output" == *$'home notes hooks\tFAIL\tmissing: pre-commit post-checkout'* ]]
}

@test "agent:smoke fails when module manifest is encrypted" {
  home="$TEST_TMPDIR/home"
  make_git_repo "$home"
  add_prepare_task "$home"
  mkdir -p "$home/.modules"
  touch "$home/.modules/config"
  printf 'GITCRYPT' > "$home/.modules/manifest"

  run fold_task agent:smoke --home "$home"

  [ "$status" -ne 0 ]
  [[ "$output" == *$'home modules manifest\tFAIL\tmissing or encrypted'* ]]
}
