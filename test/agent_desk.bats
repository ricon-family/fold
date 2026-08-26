#!/usr/bin/env bats

bats_require_minimum_version 1.5.0
load test_helper

setup() {
  TMPBIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$TMPBIN"
  export PATH="$TMPBIN:$PATH"
  export SHELL_LOG="$BATS_TEST_TMPDIR/shell.log"
  export SHELL_STATUS_MODE="ok"
  export SHELL_RUN_MARKER="$BATS_TEST_TMPDIR/shell-ran"
  export SHELL_EXITED_MARKER="$BATS_TEST_TMPDIR/shell-exited"
  export SESSIONS_LOG="$BATS_TEST_TMPDIR/sessions.log"
  export SESSIONS_ENV_LOG="$BATS_TEST_TMPDIR/sessions-env.log"
  export SESSIONS_CALLS="$BATS_TEST_TMPDIR/sessions-calls"
  printf '0\n' > "$SESSIONS_CALLS"
  export FAKE_SESSIONS_MODE="ready"
  export FAKE_GITHUB_LOGIN="quick-ricon"
  write_fake_shell
  write_fake_sessions
  write_fake_gh
}

write_fake_shell() {
  cat > "$TMPBIN/shell" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'shell %s\n' "$*" >> "${SHELL_LOG:?}"
case "${1:-}" in
  status)
    if [ "${SHELL_STATUS_MODE:-ok}" = fail ]; then
      echo "not found"
      exit 1
    fi
    if [ -f "${SHELL_EXITED_MARKER:?}" ]; then
      echo "exited (1)"
      exit 1
    fi
    echo "running"
    ;;
  history)
    printf 'line one\nline two\nline three\n'
    ;;
  run)
    : > "${SHELL_RUN_MARKER:?}"
    if [ "${SHELL_STATUS_MODE:-ok}" = fail-after-run ]; then
      : > "${SHELL_EXITED_MARKER:?}"
    fi
    echo "${5:-}"
    ;;
  *)
    echo "unexpected shell command: $*" >&2
    exit 2
    ;;
esac
SH
  chmod +x "$TMPBIN/shell"
  export SHELL_BIN="$TMPBIN/shell"
}

write_fake_sessions() {
  cat > "$TMPBIN/sessions" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'sessions %s\n' "$*" >> "${SESSIONS_LOG:?}"
if [ "${1:-}" = wake ]; then
  {
    printf 'AGENT_HOME=%s\n' "${AGENT_HOME:-unset}"
    printf 'AGENT_IDENTITY=%s\n' "${AGENT_IDENTITY:-unset}"
    printf 'GIT_AUTHOR_NAME=%s\n' "${GIT_AUTHOR_NAME:-unset}"
    printf 'GIT_AUTHOR_EMAIL=%s\n' "${GIT_AUTHOR_EMAIL:-unset}"
    printf 'GIT_COMMITTER_NAME=%s\n' "${GIT_COMMITTER_NAME:-unset}"
    printf 'GIT_COMMITTER_EMAIL=%s\n' "${GIT_COMMITTER_EMAIL:-unset}"
    printf 'GH_TOKEN=%s\n' "${GH_TOKEN:-unset}"
    printf 'GIT_CONFIG_COUNT=%s\n' "${GIT_CONFIG_COUNT:-unset}"
  } > "${SESSIONS_ENV_LOG:?}"
  exit 0
fi

call_count=$(($(cat "${SESSIONS_CALLS:?}") + 1))
printf '%s\n' "$call_count" > "$SESSIONS_CALLS"
if [ "${1:-}" != ps ] || [ "${2:-}" != --all ] || [ "${3:-}" != --json ]; then
  echo "unexpected sessions command: $*" >&2
  exit 2
fi
if [ "${FAKE_SESSIONS_MODE:-ready}" = invalid ]; then
  printf '{not-json}\n'
  exit 0
fi
if [ "${FAKE_SESSIONS_MODE:-ready}" = fail ]; then
  echo "sessions failed intentionally" >&2
  exit 42
fi
mode="${FAKE_SESSIONS_MODE:-ready}"
if [ "$mode" = deadline-edge ] && [ "$call_count" -eq 2 ]; then
  sleep "${FAKE_SESSIONS_DELAY:-1.1}"
fi
session_ready=false
if [ -f "${SHELL_RUN_MARKER:?}" ]; then
  case "$mode" in
    ready) session_ready=true ;;
    deadline-edge) [ "$call_count" -ge 3 ] && session_ready=true ;;
  esac
fi
if [ -z "${FAKE_SESSION_CWD:-}" ]; then
  printf '[]\n'
elif [ -n "${FAKE_TARGET_SESSION_ID:-}" ]; then
  if [ "$session_ready" = true ]; then
    jq -n --arg cwd "$FAKE_SESSION_CWD" --arg id "$FAKE_TARGET_SESSION_ID" \
      '[{session_id:$id,status:"exited",cwd:$cwd,harness:"pi",pid:101,process_start_id:"old-start"},{session_id:$id,status:"live",cwd:$cwd,harness:"pi",pid:202,process_start_id:"new-start"}]'
  else
    jq -n --arg cwd "$FAKE_SESSION_CWD" --arg id "$FAKE_TARGET_SESSION_ID" \
      '[{session_id:$id,status:"exited",cwd:$cwd,harness:"pi",pid:101,process_start_id:"old-start"}]'
  fi
elif [ "$session_ready" = true ]; then
  jq -n --arg cwd "$FAKE_SESSION_CWD" \
    '[{session_id:"old-pi-session",status:"live",cwd:$cwd,harness:"pi",pid:101,process_start_id:"old-start"},{session_id:"new-pi-session",status:"live",cwd:$cwd,harness:"pi",pid:202,process_start_id:"new-start"}]'
else
  jq -n --arg cwd "$FAKE_SESSION_CWD" \
    '[{session_id:"old-pi-session",status:"live",cwd:$cwd,harness:"pi",pid:101,process_start_id:"old-start"}]'
fi
SH
  chmod +x "$TMPBIN/sessions"
  export SESSIONS_BIN="$TMPBIN/sessions"
}

write_fake_gh() {
  cat > "$TMPBIN/gh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = api ] && [ "${2:-}" = user ] && [ "${3:-}" = --jq ] && [ "${4:-}" = .login ]; then
  [ "${GH_TOKEN:-}" = quick-target-token ] || {
    echo "wrong GitHub token" >&2
    exit 1
  }
  printf '%s\n' "${FAKE_GITHUB_LOGIN:-quick-ricon}"
  exit 0
fi
echo "unexpected gh command: $*" >&2
exit 2
SH
  chmod +x "$TMPBIN/gh"
  export GH_BIN="$TMPBIN/gh"
}

write_target_identity_shimmer() {
  cat > "$TMPBIN/shimmer" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  as)
    if [ "${REQUIRE_CLEAN_PARENT:-false}" = true ]; then
      [ -z "${AGENT_HOME:-}" ]
      [ -z "${AGENT_IDENTITY:-}" ]
      [ -z "${CHAT_IDENTITY:-}" ]
      [ -z "${EMAILS_CONFIG:-}" ]
      [ -z "${HIMALAYA_CONFIG:-}" ]
      [ -z "${GH_TOKEN:-}" ]
      [ -z "${GITHUB_TOKEN:-}" ]
      [ -z "${GH_CONFIG_DIR:-}" ]
      [ -z "${GIT_AUTHOR_NAME:-}" ]
      [ -z "${GIT_AUTHOR_EMAIL:-}" ]
      [ -z "${GIT_COMMITTER_NAME:-}" ]
      [ -z "${GIT_COMMITTER_EMAIL:-}" ]
      [ -z "${GIT_CONFIG_COUNT:-}" ]
      [ -z "${GIT_CONFIG_KEY_0:-}" ]
      [ -z "${GIT_CONFIG_VALUE_0:-}" ]
      [ -z "${__MISE_DIFF:-}" ]
    fi
    printf 'export AGENT_HOME=%q\n' "${FAKE_IDENTITY_HOME:-$PWD}"
    printf 'export GIT_AUTHOR_NAME=quick\n'
    printf 'export GIT_AUTHOR_EMAIL=quick@ricon.family\n'
    printf 'export GIT_COMMITTER_NAME=quick\n'
    printf 'export GIT_COMMITTER_EMAIL=quick@ricon.family\n'
    printf 'export GH_TOKEN=quick-target-token\n'
    printf 'export GIT_CONFIG_COUNT=4\n'
    printf 'export GIT_CONFIG_KEY_0=user.name\n'
    printf 'export GIT_CONFIG_VALUE_0=quick\n'
    printf 'export GIT_CONFIG_KEY_1=user.email\n'
    printf 'export GIT_CONFIG_VALUE_1=quick@ricon.family\n'
    printf 'export GIT_CONFIG_KEY_2=user.signingkey\n'
    printf 'export GIT_CONFIG_VALUE_2=%q\n' "${FAKE_ACTIVE_SIGNING_KEY:-AABBCCDDEEFF0011}"
    printf 'export GIT_CONFIG_KEY_3=commit.gpgsign\n'
    printf 'export GIT_CONFIG_VALUE_3=true\n'
    ;;
  agent)
    {
      printf 'AGENT_HOME=%s\n' "${AGENT_HOME:-unset}"
      printf 'AGENT_IDENTITY=%s\n' "${AGENT_IDENTITY:-unset}"
      printf 'CHAT_IDENTITY=%s\n' "${CHAT_IDENTITY:-unset}"
      printf 'EMAILS_CONFIG=%s\n' "${EMAILS_CONFIG:-unset}"
      printf 'HIMALAYA_CONFIG=%s\n' "${HIMALAYA_CONFIG:-unset}"
      printf '__MISE_DIFF=%s\n' "${__MISE_DIFF:-unset}"
      printf 'GIT_AUTHOR_NAME=%s\n' "${GIT_AUTHOR_NAME:-unset}"
      printf 'GIT_AUTHOR_EMAIL=%s\n' "${GIT_AUTHOR_EMAIL:-unset}"
      printf 'GIT_COMMITTER_NAME=%s\n' "${GIT_COMMITTER_NAME:-unset}"
      printf 'GIT_COMMITTER_EMAIL=%s\n' "${GIT_COMMITTER_EMAIL:-unset}"
      printf 'GH_TOKEN=%s\n' "${GH_TOKEN:-unset}"
    } > "${AGENT_LOG:?}"
    ;;
  *) exit 2 ;;
esac
SH
  chmod +x "$TMPBIN/shimmer"
}

write_fake_mise_for_prepare() {
  cat > "$TMPBIN/nested-mise" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'mise %s\n' "$*" >> "${MISE_LOG:?}"
case "${1:-} ${2:-}" in
  "run homes:auth:setup")
    home=""
    while [ "$#" -gt 0 ]; do
      if [ "$1" = "--home" ]; then
        home="${2:-}"
        break
      fi
      shift
    done
    if [ -z "$home" ]; then
      echo "homes:auth:setup missing --home" >&2
      exit 2
    fi
    mkdir -p "$(dirname "$home")"
    printf '[user]\n\tname = fixture\n' > "$(dirname "$home")/.gitconfig"
    ;;
  "run homes:adopt-remote")
    home=""
    while [ "$#" -gt 0 ]; do
      if [ "$1" = "--home" ]; then
        home="${2:-}"
        break
      fi
      shift
    done
    if [ -z "$home" ]; then
      echo "homes:adopt-remote missing --home" >&2
      exit 2
    fi
    if [ ! -f "$(dirname "$home")/.gitconfig" ]; then
      echo "auth not set up before adopt" >&2
      exit 1
    fi
    mkdir -p "$home"
    git init -q -b main "$home"
    git -C "$home" config user.name fixture
    git -C "$home" config user.email fixture@example.test
    git -C "$home" config commit.gpgsign false
    printf 'prepared home\n' > "$home/AGENTS.md"
    git -C "$home" add AGENTS.md
    git -C "$home" commit -q -m 'prepared home'
    ;;
  "run homes:email:setup")
    home=""
    while [ "$#" -gt 0 ]; do
      if [ "$1" = "--home" ]; then
        home="${2:-}"
        break
      fi
      shift
    done
    if [ -z "$home" ] || [ ! -d "$home/.git" ]; then
      echo "homes:email:setup requires adopted --home" >&2
      exit 2
    fi
    mkdir -p "$home/.emails"
    printf 'fixture email config\n' > "$home/.emails/himalaya.toml"
    ;;
  "run homes:status")
    home=""
    while [ "$#" -gt 0 ]; do
      if [ "$1" = "--home" ]; then
        home="${2:-}"
        break
      fi
      shift
    done
    if [ -z "$home" ]; then
      echo "homes:status missing --home" >&2
      exit 2
    fi
    if [ ! -f "$(dirname "$home")/.gitconfig" ]; then
      printf '{"ready":false,"next":"mise run homes:auth:setup --yes"}\n'
      exit 1
    fi
    printf '{"ready":true}\n'
    ;;
  *)
    echo "unexpected mise command: $*" >&2
    exit 2
    ;;
esac
SH
  chmod +x "$TMPBIN/nested-mise"
  export MISE="$TMPBIN/nested-mise"
  export MISE_LOG="$BATS_TEST_TMPDIR/mise.log"
  : > "$MISE_LOG"
}

write_fake_desks() {
  cat > "$TMPBIN/desks" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'desks %s\n' "$*" >> "${DESKS_LOG:?}"
root="${FAKE_DESKS_ROOT:?FAKE_DESKS_ROOT not set}"
case "${1:-}" in
  new)
    [ "${2:-}" = "--id" ] || { echo "expected --id" >&2; exit 2; }
    id="${3:?id required}"
    mkdir -p "$root/$id/.desk"
    printf '{"id":"%s"}\n' "$id" > "$root/$id/.desk/registry.json"
    ;;
  path)
    id="${2:?id required}"
    [ -d "$root/$id" ] || { echo "desk not found: $id" >&2; exit 1; }
    printf '%s/%s\n' "$root" "$id"
    ;;
  *)
    echo "unexpected desks command: $*" >&2
    exit 2
    ;;
esac
SH
  chmod +x "$TMPBIN/desks"
  export DESKS="$TMPBIN/desks"
  export DESKS_LOG="$BATS_TEST_TMPDIR/desks.log"
  export FAKE_DESKS_ROOT="$BATS_TEST_TMPDIR/desks-root"
  mkdir -p "$FAKE_DESKS_ROOT"
  : > "$DESKS_LOG"
}

make_repo() {
  local repo="$1" name="$2"
  mkdir -p "$repo"
  git init -q -b main "$repo"
  if [ "$name" = home ]; then
    git -C "$repo" config user.name quick
    git -C "$repo" config user.email quick@ricon.family
  else
    git -C "$repo" config user.name fixture
    git -C "$repo" config user.email fixture@example.test
  fi
  git -C "$repo" config user.signingkey AABBCCDDEEFF0011
  git -C "$repo" config commit.gpgsign false
  printf '%s\n' "$name" > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m "initial $name"
  if [ "$name" = home ]; then
    git -C "$repo" config commit.gpgsign true
    git -C "$repo" remote add origin https://github.com/quick-ricon/home.git
  fi
}

@test "agent:desk:prepare dry-run plans an existing desk without mutation" {
  desk="$BATS_TEST_TMPDIR/desks/probe"
  mkdir -p "$desk/.desk"
  printf '{"id":"probe"}\n' > "$desk/.desk/registry.json"
  desk_path="$desk"

  run fold_task agent:desk:prepare quick \
    --desk "$desk" \
    --repo quick-ricon/home \
    --shell quick-probe \
    --packet /tmp/packet.md

  [ "$status" -eq 0 ]
  [[ "$output" == *"Agent desk prepare"* ]]
  [[ "$output" == *"mode:    dry-run"* ]]
  [[ "$output" == *"desk:    $desk_path"* ]]
  [[ "$output" == *"home:    $desk_path/home"* ]]
  [[ "$output" == *"repo:    quick-ricon/home"* ]]
  [[ "$output" == *"dry-run: rerun with --yes"* ]]
  [[ "$output" == *"setup auth: mise run homes:auth:setup quick --home $desk_path/home --yes"* ]]
  [[ "$output" == *"setup email: mise run homes:email:setup quick --home $desk_path/home --yes"* ]]
  [[ "$output" == *"mise run agent:desk:wake quick --desk $desk_path --shell quick-probe --packet /tmp/packet.md --model '<model>' --yes"* ]]
  [ ! -e "$desk/home" ]
}

@test "agent:desk:prepare --yes provisions an existing desk through homes primitives" {
  desk="$BATS_TEST_TMPDIR/desks/probe"
  mkdir -p "$desk/.desk"
  printf '{"id":"probe"}\n' > "$desk/.desk/registry.json"
  desk_path="$desk"
  write_fake_mise_for_prepare

  run fold_task agent:desk:prepare quick \
    --desk "$desk" \
    --repo quick-ricon/home \
    --shell quick-probe \
    --packet /tmp/packet.md \
    --yes

  [ "$status" -eq 0 ]
  [[ "$output" == *"== setup home auth =="* ]]
  [[ "$output" == *"== adopt home =="* ]]
  [[ "$output" == *"== setup home email =="* ]]
  [[ "$output" == *"== verify home readiness =="* ]]
  [[ "$output" == *"Ready. Next wake command:"* ]]
  auth_line=$(grep -nF "mise run homes:auth:setup quick --home $desk_path/home --yes" "$MISE_LOG" | cut -d: -f1)
  adopt_line=$(grep -nF "mise run homes:adopt-remote quick --home $desk_path/home --branch main --yes --repo quick-ricon/home" "$MISE_LOG" | cut -d: -f1)
  email_line=$(grep -nF "mise run homes:email:setup quick --home $desk_path/home --yes" "$MISE_LOG" | cut -d: -f1)
  status_line=$(grep -nF "mise run homes:status quick --home $desk_path/home --json --check" "$MISE_LOG" | cut -d: -f1)
  [ "$auth_line" -lt "$adopt_line" ]
  [ "$adopt_line" -lt "$email_line" ]
  [ "$email_line" -lt "$status_line" ]
  [ -f "$desk/.gitconfig" ]
  [ -d "$desk/home/.git" ]
  [ -f "$desk/home/.emails/himalaya.toml" ]
  if [ -f "$SHELL_LOG" ]; then
    ! grep -q 'shell run' "$SHELL_LOG"
  fi
}

@test "agent:desk:prepare --yes can create a desk through desks new" {
  write_fake_mise_for_prepare
  write_fake_desks
  export FOLD_AGENT_DESK_PREPARE_TIMESTAMP=20260620133700

  run fold_task agent:desk:prepare quick \
    --purpose rewind-investigation \
    --repo quick-ricon/home \
    --packet /tmp/packet.md \
    --yes

  [ "$status" -eq 0 ]
  desk_id="quick-rewind-investigation-20260620133700"
  desk="$FAKE_DESKS_ROOT/$desk_id"
  grep -F "desks new --id $desk_id" "$DESKS_LOG" >/dev/null
  grep -F "desks path $desk_id" "$DESKS_LOG" >/dev/null
  auth_line=$(grep -nF "mise run homes:auth:setup quick --home $desk/home --yes" "$MISE_LOG" | cut -d: -f1)
  adopt_line=$(grep -nF "mise run homes:adopt-remote quick --home $desk/home --branch main --yes --repo quick-ricon/home" "$MISE_LOG" | cut -d: -f1)
  email_line=$(grep -nF "mise run homes:email:setup quick --home $desk/home --yes" "$MISE_LOG" | cut -d: -f1)
  [ "$auth_line" -lt "$adopt_line" ]
  [ "$adopt_line" -lt "$email_line" ]
  [[ "$output" == *"desk id: $desk_id"* ]]
  [[ "$output" == *"mise run agent:desk:wake quick --desk $desk --shell $desk_id --packet /tmp/packet.md --model '<model>' --yes"* ]]
  [ -f "$desk/.desk/registry.json" ]
  [ -f "$desk/.gitconfig" ]
  [ -d "$desk/home/.git" ]
}

@test "agent:desk:prepare refuses to mutate a missing explicit desk path" {
  write_fake_mise_for_prepare

  run fold_task agent:desk:prepare quick \
    --desk "$BATS_TEST_TMPDIR/missing-desk" \
    --repo quick-ricon/home \
    --yes

  [ "$status" -ne 0 ]
  [[ "${output}${stderr:-}" == *"explicit --desk path must already exist"* ]]
  [ ! -s "$MISE_LOG" ]
}

@test "agent:desk:status inspects one explicit desk without assuming singleton agent state" {
  desk="$BATS_TEST_TMPDIR/desks/quick-a"
  mkdir -p "$desk/.desk"
  printf '{"id":"quick-a"}\n' > "$desk/.desk/registry.json"
  make_repo "$desk/home" home
  make_repo "$desk/nvr" nvr
  desk_real=$(cd "$desk" && pwd -P)

  run fold_task agent:desk:status quick --desk "$desk" --shell quick-a --recent 1

  [ "$status" -eq 0 ]
  [[ "$output" == *"agent: quick"* ]]
  [[ "$output" == *"desk:  $desk_real"* ]]
  [[ "$output" == *"name: quick-a"* ]]
  [[ "$output" == *"running"* ]]
  [[ "$output" == *"== home =="* ]]
  [[ "$output" == *"== nvr =="* ]]
}

@test "agent:desk:pi-auth shows provider metadata without token values" {
  pi_dir="$BATS_TEST_TMPDIR/pi-agent"
  mkdir -p "$pi_dir"
  cat > "$pi_dir/auth.json" <<'JSON'
{
  "openai-codex": {
    "type": "SECRET_TYPE_VALUE",
    "access_token": "SECRET_ACCESS",
    "refresh": "SECRET_REFRESH",
    "accountId": "acct_123",
    "expires": 123
  },
  "huggingface": {
    "type": "api_key",
    "key": "SECRET_KEY"
  }
}
JSON
  cat > "$pi_dir/models.json" <<'JSON'
{"providers":{"openai-codex":{},"local-vllm":{}}}
JSON

  run fold_task agent:desk:pi-auth --pi-dir "$pi_dir"

  [ "$status" -eq 0 ]
  [[ "$output" == *"openai-codex"* ]]
  [[ "$output" == *"huggingface"* ]]
  [[ "$output" == *"provider_keys"* ]]
  [[ "$output" != *"SECRET_ACCESS"* ]]
  [[ "$output" != *"SECRET_REFRESH"* ]]
  [[ "$output" != *"SECRET_KEY"* ]]
  [[ "$output" != *"SECRET_TYPE_VALUE"* ]]
  [[ "$output" == *"type_key=present"* ]]
}

@test "agent:desk:smoke can fail closed when --check is set" {
  export SHELL_STATUS_MODE=fail

  run fold_task agent:desk:smoke --shell quick-missing --history-lines 2 --check

  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
  [[ "$output" == *"line two"* ]]
  [[ "$output" == *"line three"* ]]
}

@test "agent:desk:wake requires an explicit model before rendering" {
  home="$BATS_TEST_TMPDIR/home"
  packet="$BATS_TEST_TMPDIR/packet.md"
  make_repo "$home" home
  printf 'hello packet\n' > "$packet"

  run fold_task agent:desk:wake quick --home "$home" --shell quick-a --packet "$packet"

  [ "$status" -eq 64 ]
  [[ "${output}${stderr:-}" == *"ERROR: --model is required"* ]]
}

@test "agent:desk:wake rejects a noncanonical home origin without printing credentials" {
  home="$BATS_TEST_TMPDIR/home"
  packet="$BATS_TEST_TMPDIR/packet.md"
  make_repo "$home" home
  git -C "$home" remote set-url origin https://secret-token@github.com/quick-ricon/home.git
  printf 'hello packet\n' > "$packet"

  run fold_task agent:desk:wake quick \
    --home "$home" \
    --shell quick-a \
    --packet "$packet" \
    --model openai-codex/gpt-5.6-sol

  [ "$status" -ne 0 ]
  [[ "$output" == *"target home origin is not a canonical GitHub OWNER/home URL"* ]]
  [[ "$output" != *"secret-token"* ]]
}

@test "agent:desk:wake defaults identity to the desk home" {
  home="$BATS_TEST_TMPDIR/home"
  work_dir="$BATS_TEST_TMPDIR/wake"
  packet="$BATS_TEST_TMPDIR/packet.md"
  make_repo "$home" home
  printf 'hello packet\n' > "$packet"
  home_real=$(cd "$home" && pwd -P)

  run fold_task agent:desk:wake quick --home "$home" --shell quick-a --packet "$packet" --model openai-codex/gpt-5.6-sol --work-dir "$work_dir"

  [ "$status" -eq 0 ]
  [[ "$output" == *"identity-source: $home_real"* ]]
  [[ "$output" == *"dry-run"* ]]
  [ -x "$work_dir/start-quick-a.sh" ]
  if [ -f "$SHELL_LOG" ]; then
    ! grep -q 'shell run' "$SHELL_LOG"
  fi
  repo_real=$(cd "$REPO_DIR" && pwd -P)
  grep -q "AGENT_DESK_IDENTITY_SOURCE='$home_real'" "$work_dir/start-quick-a.sh"
  grep -q "AGENT_DESK_MODEL='openai-codex/gpt-5.6-sol'" "$work_dir/start-quick-a.sh"
  grep -q "exec '$repo_real/.mise/lib/agent_desk_runtime.sh'" "$work_dir/start-quick-a.sh"
  ! grep -q 'agent_desk_runtime_scrub_inherited_identity' "$work_dir/start-quick-a.sh"
  [ "$(wc -l < "$work_dir/start-quick-a.sh")" -le 20 ]
}

@test "agent:desk:wake isolates inherited email selectors to the authenticated desk home" {
  home="$BATS_TEST_TMPDIR/home"
  work_dir="$BATS_TEST_TMPDIR/wake"
  packet="$BATS_TEST_TMPDIR/packet.md"
  agent_log="$BATS_TEST_TMPDIR/agent.log"
  make_repo "$home" home
  printf 'hello packet\n' > "$packet"
  export AGENT_LOG="$agent_log"
  export REQUIRE_CLEAN_PARENT=true
  export EMAILS_CONFIG="/agents/junior/home/.emails/himalaya.toml"
  export HIMALAYA_CONFIG="/agents/brownie/home/.emails/himalaya.toml"
  export __MISE_DIFF="stale-parent-activation"
  write_target_identity_shimmer

  fold_task agent:desk:wake quick --home "$home" --shell quick-a --packet "$packet" --model openai-codex/gpt-5.6-sol --work-dir "$work_dir" >/dev/null
  run "$work_dir/start-quick-a.sh"

  [ "$status" -eq 0 ]
  home_real=$(cd "$home" && pwd -P)
  grep -Fx "EMAILS_CONFIG=$home_real/.emails/himalaya.toml" "$agent_log"
  grep -Fx 'HIMALAYA_CONFIG=unset' "$agent_log"
  grep -Fx '__MISE_DIFF=unset' "$agent_log"
}

@test "agent:desk:wake scrubs a poisoned parent persona before target activation" {
  home="$BATS_TEST_TMPDIR/home"
  work_dir="$BATS_TEST_TMPDIR/wake"
  packet="$BATS_TEST_TMPDIR/packet.md"
  agent_log="$BATS_TEST_TMPDIR/agent.log"
  make_repo "$home" home
  printf 'hello packet\n' > "$packet"
  export AGENT_LOG="$agent_log"
  export REQUIRE_CLEAN_PARENT=true
  export AGENT_HOME="/agents/junior/home"
  export AGENT_IDENTITY=junior
  export CHAT_IDENTITY=junior
  export EMAILS_CONFIG="/agents/junior/home/.emails/himalaya.toml"
  export HIMALAYA_CONFIG="/agents/junior/home/.emails/himalaya.toml"
  export GH_TOKEN=junior-token
  export GITHUB_TOKEN=junior-github-token
  export GH_CONFIG_DIR="/agents/junior/gh"
  export GIT_AUTHOR_NAME=junior
  export GIT_AUTHOR_EMAIL=junior@ricon.family
  export GIT_COMMITTER_NAME=junior
  export GIT_COMMITTER_EMAIL=junior@ricon.family
  export GIT_CONFIG_COUNT=1
  export GIT_CONFIG_KEY_0=user.name
  export GIT_CONFIG_VALUE_0=junior
  export __MISE_DIFF="junior-activation"
  write_target_identity_shimmer

  fold_task agent:desk:wake quick --home "$home" --shell quick-a --packet "$packet" --model openai-codex/gpt-5.6-sol --work-dir "$work_dir" >/dev/null
  run "$work_dir/start-quick-a.sh"

  [ "$status" -eq 0 ]
  home_real=$(cd "$home" && pwd -P)
  grep -Fx "AGENT_HOME=$home_real" "$agent_log"
  grep -Fx 'AGENT_IDENTITY=quick' "$agent_log"
  grep -Fx 'CHAT_IDENTITY=quick' "$agent_log"
  grep -Fx 'GIT_AUTHOR_NAME=quick' "$agent_log"
  grep -Fx 'GIT_AUTHOR_EMAIL=quick@ricon.family' "$agent_log"
  grep -Fx 'GIT_COMMITTER_NAME=quick' "$agent_log"
  grep -Fx 'GIT_COMMITTER_EMAIL=quick@ricon.family' "$agent_log"
  grep -Fx 'GH_TOKEN=quick-target-token' "$agent_log"
}

@test "agent:desk:wake accepts the prepared fingerprint through its active long key ID" {
  home="$BATS_TEST_TMPDIR/home"
  work_dir="$BATS_TEST_TMPDIR/wake"
  packet="$BATS_TEST_TMPDIR/packet.md"
  agent_log="$BATS_TEST_TMPDIR/agent.log"
  make_repo "$home" home
  git -C "$home" config user.signingkey E290F2F77201FF5E0E3B75A65EA22CEE669F73CB
  printf 'hello packet\n' > "$packet"
  export AGENT_LOG="$agent_log"
  export FAKE_ACTIVE_SIGNING_KEY=5ea22cee669f73cb
  write_target_identity_shimmer

  fold_task agent:desk:wake quick --home "$home" --shell quick-a --packet "$packet" --model openai-codex/gpt-5.6-sol --work-dir "$work_dir" >/dev/null
  run "$work_dir/start-quick-a.sh"

  [ "$status" -eq 0 ]
  [ -e "$agent_log" ]
}

@test "agent:desk:wake rejects an unrelated active signing key" {
  home="$BATS_TEST_TMPDIR/home"
  work_dir="$BATS_TEST_TMPDIR/wake"
  packet="$BATS_TEST_TMPDIR/packet.md"
  agent_log="$BATS_TEST_TMPDIR/agent.log"
  make_repo "$home" home
  git -C "$home" config user.signingkey E290F2F77201FF5E0E3B75A65EA22CEE669F73CB
  printf 'hello packet\n' > "$packet"
  export AGENT_LOG="$agent_log"
  export FAKE_ACTIVE_SIGNING_KEY=1111222233334444
  write_target_identity_shimmer

  fold_task agent:desk:wake quick --home "$home" --shell quick-a --packet "$packet" --model openai-codex/gpt-5.6-sol --work-dir "$work_dir" >/dev/null
  run "$work_dir/start-quick-a.sh"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Git signing key does not match the prepared target home"* ]]
  [ ! -e "$agent_log" ]
}

@test "agent:desk:wake fails closed on a target GitHub mismatch" {
  home="$BATS_TEST_TMPDIR/home"
  work_dir="$BATS_TEST_TMPDIR/wake"
  packet="$BATS_TEST_TMPDIR/packet.md"
  agent_log="$BATS_TEST_TMPDIR/agent.log"
  make_repo "$home" home
  printf 'hello packet\n' > "$packet"
  export AGENT_LOG="$agent_log"
  export FAKE_GITHUB_LOGIN=junior-ricon
  write_target_identity_shimmer

  fold_task agent:desk:wake quick --home "$home" --shell quick-a --packet "$packet" --model openai-codex/gpt-5.6-sol --work-dir "$work_dir" >/dev/null
  run "$work_dir/start-quick-a.sh"

  [ "$status" -ne 0 ]
  [[ "$output" == *"GitHub login is junior-ricon, expected quick-ricon"* ]]
  [ ! -e "$agent_log" ]
}

@test "agent:desk:wake launcher stops when identity setup fails" {
  home="$BATS_TEST_TMPDIR/home"
  work_dir="$BATS_TEST_TMPDIR/wake"
  packet="$BATS_TEST_TMPDIR/packet.md"
  agent_log="$BATS_TEST_TMPDIR/agent.log"
  make_repo "$home" home
  printf 'hello packet\n' > "$packet"
  export AGENT_LOG="$agent_log"
  cat > "$TMPBIN/shimmer" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  as)
    printf 'unset GIT_AUTHOR_NAME AGENT_HOME\n'
    exit 23
    ;;
  agent)
    printf 'agent started\n' >> "${AGENT_LOG:?}"
    ;;
  *) exit 2 ;;
esac
SH
  chmod +x "$TMPBIN/shimmer"

  fold_task agent:desk:wake quick --home "$home" --shell quick-a --packet "$packet" --model openai-codex/gpt-5.6-sol --work-dir "$work_dir" >/dev/null
  run "$work_dir/start-quick-a.sh"

  [ "$status" -eq 23 ]
  [ ! -e "$agent_log" ]
}

@test "agent:desk:wake launcher rejects identity from another home" {
  home="$BATS_TEST_TMPDIR/home"
  wrong_home="$BATS_TEST_TMPDIR/wrong-home"
  work_dir="$BATS_TEST_TMPDIR/wake"
  packet="$BATS_TEST_TMPDIR/packet.md"
  agent_log="$BATS_TEST_TMPDIR/agent.log"
  make_repo "$home" home
  make_repo "$wrong_home" wrong
  printf 'hello packet\n' > "$packet"
  export FAKE_IDENTITY_HOME="$wrong_home"
  export AGENT_LOG="$agent_log"
  write_target_identity_shimmer

  fold_task agent:desk:wake quick --home "$home" --shell quick-a --packet "$packet" --model openai-codex/gpt-5.6-sol --work-dir "$work_dir" >/dev/null
  run "$work_dir/start-quick-a.sh"

  [ "$status" -ne 0 ]
  [[ "$output" == *"authenticated agent home does not match desk home"* ]]
  [ ! -e "$agent_log" ]
}

@test "agent:desk:wake renders relative packet paths as absolute for the launcher" {
  home="$BATS_TEST_TMPDIR/home"
  work_dir="$BATS_TEST_TMPDIR/wake"
  make_repo "$home" home
  repo_real=$(cd "$REPO_DIR" && pwd -P)

  run fold_task agent:desk:wake quick --home "$home" --shell quick-a --packet AGENTS.md --model openai-codex/gpt-5.6-sol --work-dir "$work_dir"

  [ "$status" -eq 0 ]
  grep -q "AGENT_DESK_PACKET='$repo_real/AGENTS.md'" "$work_dir/start-quick-a.sh"
}

@test "agent:desk:wake --session invokes sessions wake under a scrubbed target identity" {
  home="$BATS_TEST_TMPDIR/home"
  work_dir="$BATS_TEST_TMPDIR/continue"
  packet="$BATS_TEST_TMPDIR/follow-up.md"
  make_repo "$home" home
  printf 'continue packet\n' > "$packet"
  export REQUIRE_CLEAN_PARENT=true
  export AGENT_HOME="/agents/junior/home"
  export AGENT_IDENTITY=junior
  export CHAT_IDENTITY=junior
  export GH_TOKEN=junior-token
  export GIT_AUTHOR_NAME=junior
  export GIT_AUTHOR_EMAIL=junior@ricon.family
  export GIT_COMMITTER_NAME=junior
  export GIT_COMMITTER_EMAIL=junior@ricon.family
  export GIT_CONFIG_COUNT=1
  export GIT_CONFIG_KEY_0=user.name
  export GIT_CONFIG_VALUE_0=junior
  write_target_identity_shimmer

  fold_task agent:desk:wake quick \
    --session session-123 \
    --home "$home" \
    --shell quick-cont \
    --packet "$packet" \
    --model openai-codex/gpt-5.6-sol \
    --message "Continue the reviewed lane." \
    --work-dir "$work_dir" >/dev/null
  run "$work_dir/start-quick-cont.sh"

  [ "$status" -eq 0 ]
  home_real=$(cd "$home" && pwd -P)
  packet_real=$(cd "$(dirname "$packet")" && pwd -P)/$(basename "$packet")
  grep -F "sessions wake session-123 --model openai-codex/gpt-5.6-sol --context-file $packet_real" "$SESSIONS_LOG"
  grep -F -- "--message [agent desk wake — root handoff] Continue the reviewed lane." "$SESSIONS_LOG"
  grep -Fx "AGENT_HOME=$home_real" "$SESSIONS_ENV_LOG"
  grep -Fx 'AGENT_IDENTITY=quick' "$SESSIONS_ENV_LOG"
  grep -Fx 'GIT_AUTHOR_NAME=quick' "$SESSIONS_ENV_LOG"
  grep -Fx 'GIT_AUTHOR_EMAIL=quick@ricon.family' "$SESSIONS_ENV_LOG"
  grep -Fx 'GIT_COMMITTER_NAME=quick' "$SESSIONS_ENV_LOG"
  grep -Fx 'GIT_COMMITTER_EMAIL=quick@ricon.family' "$SESSIONS_ENV_LOG"
  grep -Fx 'GH_TOKEN=quick-target-token' "$SESSIONS_ENV_LOG"
  grep -Fx 'GIT_CONFIG_COUNT=4' "$SESSIONS_ENV_LOG"
}

@test "agent:desk:wake --session detects a new process for the same session ID" {
  home="$BATS_TEST_TMPDIR/home"
  work_dir="$BATS_TEST_TMPDIR/continue"
  packet="$BATS_TEST_TMPDIR/follow-up.md"
  make_repo "$home" home
  printf 'continue packet\n' > "$packet"
  home_real=$(cd "$home" && pwd -P)
  export FAKE_SESSION_CWD="$home_real"
  export FAKE_TARGET_SESSION_ID=session-123

  run fold_task agent:desk:wake quick \
    --session session-123 \
    --home "$home" \
    --shell quick-cont \
    --packet "$packet" \
    --model openai-codex/gpt-5.6-sol \
    --work-dir "$work_dir" \
    --yes

  [ "$status" -eq 0 ]
  [[ "$output" == *"Agent wake ready"* ]]
  [[ "$output" == *"mode:    resume"* ]]
  [[ "$output" == *"session: session-123"* ]]
  [[ "$output" == *"attach:  shell attach quick-cont"* ]]
  work_real=$(cd "$work_dir" && pwd -P)
  grep -q "shell run --cwd $home_real quick-cont $work_real/start-quick-cont.sh" "$SHELL_LOG"
  [ "$(cat "$SESSIONS_CALLS")" -ge 2 ]
}

@test "agent:desk:wake --yes waits for a new live Pi process" {
  home="$BATS_TEST_TMPDIR/home"
  work_dir="$BATS_TEST_TMPDIR/wake"
  packet="$BATS_TEST_TMPDIR/packet.md"
  make_repo "$home" home
  printf 'hello packet\n' > "$packet"

  home_real=$(cd "$home" && pwd -P)
  export FAKE_SESSION_CWD="$home_real"

  run fold_task agent:desk:wake quick --home "$home" --shell quick-a --packet "$packet" --model openai-codex/gpt-5.6-sol --work-dir "$work_dir" --yes

  [ "$status" -eq 0 ]
  [[ "$output" == *"launching fresh wake in shell quick-a"* ]]
  [[ "$output" == *"Agent wake ready"* ]]
  [[ "$output" == *"mode:    fresh"* ]]
  [[ "$output" == *"session: new-pi-session"* ]]
  [[ "$output" == *"attach:  shell attach quick-a"* ]]
  work_real=$(cd "$work_dir" && pwd -P)
  grep -q "shell run --cwd $home_real quick-a $work_real/start-quick-a.sh" "$SHELL_LOG"
  grep -q "sessions ps --all --json" "$SESSIONS_LOG"
}

@test "agent:desk:wake makes a final observation after a slow deadline-edge probe" {
  home="$BATS_TEST_TMPDIR/home"
  work_dir="$BATS_TEST_TMPDIR/wake"
  packet="$BATS_TEST_TMPDIR/packet.md"
  make_repo "$home" home
  printf 'hello packet\n' > "$packet"
  export FAKE_SESSION_CWD="$(cd "$home" && pwd -P)"
  export FAKE_SESSIONS_MODE=deadline-edge
  export FAKE_SESSIONS_DELAY=1.1

  run fold_task agent:desk:wake quick --home "$home" --shell quick-a --packet "$packet" --model openai-codex/gpt-5.6-sol --startup-timeout 1 --work-dir "$work_dir" --yes

  [ "$status" -eq 0 ]
  [[ "$output" == *"Agent wake ready"* ]]
  [[ "$output" == *"session: new-pi-session"* ]]
  [ "$(cat "$SESSIONS_CALLS")" -ge 3 ]
}

@test "agent:desk:wake rejects a running shell without a new Pi process" {
  home="$BATS_TEST_TMPDIR/home"
  work_dir="$BATS_TEST_TMPDIR/wake"
  packet="$BATS_TEST_TMPDIR/packet.md"
  make_repo "$home" home
  printf 'hello packet\n' > "$packet"
  export FAKE_SESSION_CWD="$(cd "$home" && pwd -P)"
  export FAKE_SESSIONS_MODE=never

  run fold_task agent:desk:wake quick --home "$home" --shell quick-a --packet "$packet" --model openai-codex/gpt-5.6-sol --startup-timeout 1 --work-dir "$work_dir" --yes

  [ "$status" -ne 0 ]
  [[ "$output" == *"no new live Pi process appeared during the 1s window or final observation"* ]]
  [[ "$output" == *"line one"* ]]
}

@test "agent:desk:wake surfaces a shell that exits before Pi starts" {
  home="$BATS_TEST_TMPDIR/home"
  work_dir="$BATS_TEST_TMPDIR/wake"
  packet="$BATS_TEST_TMPDIR/packet.md"
  make_repo "$home" home
  printf 'hello packet\n' > "$packet"
  export FAKE_SESSION_CWD="$(cd "$home" && pwd -P)"
  export FAKE_SESSIONS_MODE=never
  export SHELL_STATUS_MODE=fail-after-run

  run fold_task agent:desk:wake quick --home "$home" --shell quick-a --packet "$packet" --model openai-codex/gpt-5.6-sol --startup-timeout 5 --work-dir "$work_dir" --yes

  [ "$status" -ne 0 ]
  [[ "$output" == *"agent shell exited before Pi became ready"* ]]
  [[ "$output" == *"exited (1)"* ]]
}
