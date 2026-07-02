#!/usr/bin/env bash
# Shared entrypoint for fold homes:ci:* mise task helpers.
#
# This is a lib, not a mise task. Self-locate via BASH_SOURCE rather than
# reading MISE_CONFIG_ROOT; agent sessions can inherit a stale MCR from the
# launcher repo. See fold/notes/mise-gotchas.md.
set -euo pipefail

HOMES_CI_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOMES_CI_LIB_ROOT="$(cd "$HOMES_CI_LIB_DIR/.." && pwd)"
HOMES_CI_COMPONENT_DIR="$HOMES_CI_LIB_DIR/ci"
# shellcheck source=.mise/lib/common.sh
source "$HOMES_CI_LIB_ROOT/common.sh"

HOMES_CI_JQ_BIN="${JQ:-jq}"
export HOMES_CI_JQ_BIN

homes_ci_die() {
  echo "ERROR: $*" >&2
  exit 1
}

homes_ci_require_tools() {
  require_tool "$GH_BIN" "$SECRETS_BIN" "$HOMES_CI_JQ_BIN" xargs sed tr grep
}

# shellcheck source=.mise/lib/homes/ci/targets.sh
source "$HOMES_CI_COMPONENT_DIR/targets.sh"
# shellcheck source=.mise/lib/homes/ci/secrets.sh
source "$HOMES_CI_COMPONENT_DIR/secrets.sh"
# shellcheck source=.mise/lib/homes/ci/status.sh
source "$HOMES_CI_COMPONENT_DIR/status.sh"
# shellcheck source=.mise/lib/homes/ci/sync.sh
source "$HOMES_CI_COMPONENT_DIR/sync.sh"
