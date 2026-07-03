#!/usr/bin/env bash
# Shared entrypoint for fold github:ci:* mise task helpers.
#
# This is a lib, not a mise task. Self-locate via BASH_SOURCE rather than
# reading MISE_CONFIG_ROOT; agent sessions can inherit a stale MCR from the
# launcher repo. See fold/notes/mise-gotchas.md.
set -euo pipefail

GITHUB_CI_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITHUB_CI_LIB_ROOT="$(cd "$GITHUB_CI_LIB_DIR/.." && pwd)"
GITHUB_CI_COMPONENT_DIR="$GITHUB_CI_LIB_DIR/ci"
# shellcheck source=.mise/lib/common.sh
source "$GITHUB_CI_LIB_ROOT/common.sh"

GITHUB_CI_JQ_BIN="${JQ:-jq}"
export GITHUB_CI_JQ_BIN

github_ci_die() {
  echo "ERROR: $*" >&2
  exit 1
}

github_ci_require_tools() {
  require_tool "$GH_BIN" "$SECRETS_BIN" "$GITHUB_CI_JQ_BIN" xargs sed tr grep
}

# shellcheck source=.mise/lib/github/ci/targets.sh
source "$GITHUB_CI_COMPONENT_DIR/targets.sh"
# shellcheck source=.mise/lib/github/ci/secrets.sh
source "$GITHUB_CI_COMPONENT_DIR/secrets.sh"
# shellcheck source=.mise/lib/github/ci/status.sh
source "$GITHUB_CI_COMPONENT_DIR/status.sh"
# shellcheck source=.mise/lib/github/ci/sync.sh
source "$GITHUB_CI_COMPONENT_DIR/sync.sh"
