write_fake_mise_for_prepare() {
  cat > "$TMPBIN/nested-mise" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'mise %s\n' "$*" >> "${MISE_LOG:?}"

case "${1:-} ${2:-}" in
  "run homes:auth")
    if [[ " $* " != *" --check "* ]]; then
      exit 2
    fi
    if [ "${FAKE_AUTH_PREREQUISITES_FAIL:-false}" = true ]; then
      printf '{"ready":false}\n'
      exit 1
    fi
    printf '{"ready":true}\n'
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
    if ! grep -q 'mise run homes:auth .* --json --check' "$MISE_LOG"; then
      echo "auth prerequisites not checked before adopt" >&2
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
    if [ "${EMAIL_ACCOUNTS:-}" != fixture ]; then
      echo 'persona email environment missing' >&2
      exit 1
    fi
    if [ "${FAKE_EMAIL_INPUTS_FAIL:-false}" = true ]; then
      echo 'incomplete email inputs' >&2
      exit 1
    fi
    if [[ " $* " != *" --yes "* ]]; then
      exit 0
    fi

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
    if [ ! -d "$home/.git" ]; then
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

  cat > "$TMPBIN/prepare-shimmer" <<'SH'
#!/usr/bin/env bash
if [ "$1" != as ] || [ "$2" != quick ]; then
  exit 2
fi
if [ "${FAKE_PERSONA_FAIL:-false}" = true ]; then
  exit 1
fi

printf 'export EMAIL_ACCOUNTS=fixture\n'
SH
  chmod +x "$TMPBIN/prepare-shimmer"
  export SHIMMER="$TMPBIN/prepare-shimmer"
}

write_fake_desks() {
  cat > "$TMPBIN/desks" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'desks %s\n' "$*" >> "${DESKS_LOG:?}"
root="${FAKE_DESKS_ROOT:?FAKE_DESKS_ROOT not set}"

case "${1:-}" in
  new)
    if [ "${2:-}" != "--id" ]; then
      echo "expected --id" >&2
      exit 2
    fi

    id="${3:?id required}"
    mkdir -p "$root/$id/.desk"
    printf '{"id":"%s"}\n' "$id" > "$root/$id/.desk/registry.json"
    ;;

  path)
    id="${2:?id required}"
    if [ ! -d "$root/$id" ]; then
      echo "desk not found: $id" >&2
      exit 1
    fi

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

