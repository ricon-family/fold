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
  export SESSIONS_CALLS="$BATS_TEST_TMPDIR/sessions-calls"
  printf '0\n' > "$SESSIONS_CALLS"
  export FAKE_SESSIONS_MODE="ready"
  write_fake_shell
  write_fake_sessions
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
elif [ "$session_ready" = true ]; then
  jq -n --arg cwd "$FAKE_SESSION_CWD" \
    '[{session_id:"old-pi-session",status:"live",cwd:$cwd,harness:"pi"},{session_id:"new-pi-session",status:"live",cwd:$cwd,harness:"pi"}]'
else
  jq -n --arg cwd "$FAKE_SESSION_CWD" \
    '[{session_id:"old-pi-session",status:"live",cwd:$cwd,harness:"pi"}]'
fi
SH
  chmod +x "$TMPBIN/sessions"
  export SESSIONS_BIN="$TMPBIN/sessions"
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
  git -C "$repo" config user.name fixture
  git -C "$repo" config user.email fixture@example.test
  git -C "$repo" config commit.gpgsign false
  printf '%s\n' "$name" > "$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m "initial $name"
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
  [[ "$output" == *"== verify home readiness =="* ]]
  [[ "$output" == *"Ready. Next wake command:"* ]]
  auth_line=$(grep -nF "mise run homes:auth:setup quick --home $desk_path/home --yes" "$MISE_LOG" | cut -d: -f1)
  adopt_line=$(grep -nF "mise run homes:adopt-remote quick --home $desk_path/home --branch main --yes --repo quick-ricon/home" "$MISE_LOG" | cut -d: -f1)
  status_line=$(grep -nF "mise run homes:status quick --home $desk_path/home --json --check" "$MISE_LOG" | cut -d: -f1)
  [ "$auth_line" -lt "$adopt_line" ]
  [ "$adopt_line" -lt "$status_line" ]
  [ -f "$desk/.gitconfig" ]
  [ -d "$desk/home/.git" ]
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
  [ "$auth_line" -lt "$adopt_line" ]
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
  grep -q "IDENTITY_SOURCE='$home_real'" "$work_dir/start-quick-a.sh"
  grep -q 'shimmer as "$AGENT"' "$work_dir/start-quick-a.sh"
  grep -q 'MODEL='"'"'openai-codex/gpt-5.6-sol'"'"'' "$work_dir/start-quick-a.sh"
  grep -q 'shimmer agent --model "$MODEL"' "$work_dir/start-quick-a.sh"
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
  export WRONG_HOME="$wrong_home"
  export AGENT_LOG="$agent_log"
  cat > "$TMPBIN/shimmer" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  as)
    printf 'export AGENT_HOME=%q\n' "${WRONG_HOME:?}"
    printf 'export GIT_AUTHOR_NAME=quick\n'
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
  grep -q "PACKET_PATH='$repo_real/AGENTS.md'" "$work_dir/start-quick-a.sh"
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
  [[ "$output" == *"launching shell quick-a"* ]]
  [[ "$output" == *"Agent runtime ready"* ]]
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
  [[ "$output" == *"Agent runtime ready"* ]]
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
