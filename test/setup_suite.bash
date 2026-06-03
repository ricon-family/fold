setup_suite() {
  export REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  eval "$(cd "$REPO_DIR" && mise env)"
}
