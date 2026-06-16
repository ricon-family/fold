setup_suite() {
  local bats_libexec="${BATS_LIBEXEC:-}"
  REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export REPO_DIR
  eval "$(cd "$REPO_DIR" && mise env)"
  if [ -n "$bats_libexec" ]; then
    export PATH="$bats_libexec:$PATH"
  fi
}
