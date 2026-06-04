fold_task() {
  cd "$REPO_DIR" && mise run -q "$@"
}
export -f fold_task

write_mock_secrets() {
  local path="$BATS_TEST_TMPDIR/secrets"
  cat > "$path" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" != "get" ]; then
  echo "unexpected secrets command: $*" >&2
  exit 2
fi
case "${2:-}" in
  rho/github-username) echo "rho-ricon" ;;
  rho/github-pat) echo "token-rho" ;;
  quick/github-username) echo "quick-ricon" ;;
  quick/github-pat) echo "token-quick" ;;
  *) echo "missing secret: ${2:-}" >&2; exit 1 ;;
esac
SH
  chmod +x "$path"
  export SECRETS="$path"
}

write_mock_gh() {
  local path="$BATS_TEST_TMPDIR/gh"
  : "${MOCK_GH_LOG:=$BATS_TEST_TMPDIR/gh.log}"
  : > "$MOCK_GH_LOG"
  export MOCK_GH_LOG
  cat > "$path" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'GH_TOKEN=%s ARGS=%s\n' "${GH_TOKEN:-ambient}" "$*" >> "${MOCK_GH_LOG:?}"

if [ "${1:-}" = "api" ] && [ "${2:-}" = "user" ]; then
  case "${GH_TOKEN:-ambient}" in
    token-rho) echo "rho-ricon" ;;
    token-quick) echo "quick-ricon" ;;
    *) echo "or-operator" ;;
  esac
  exit 0
fi

if [ "${1:-}" = "api" ] && [ "${2:-}" = "-X" ] && [ "${3:-}" = "PUT" ]; then
  case "${4:-}" in
    /repos/rikonor/ideas/collaborators/rho-ricon|/repos/rikonor/ideas/collaborators/quick-ricon)
      exit 0
      ;;
  esac
fi

if [ "${1:-}" = "api" ] && [[ "${2:-}" == /repos/rikonor/ideas/collaborators/*/permission ]]; then
  echo "write"
  exit 0
fi

if [ "${1:-}" = "api" ] && [ "${2:-}" = "/user/repository_invitations" ]; then
  jq_filter=""
  for ((i = 3; i <= $#; i++)); do
    arg="${!i}"
    if [ "$arg" = "--jq" ]; then
      next=$((i + 1))
      jq_filter="${!next:-}"
      break
    fi
  done

  case "${GH_TOKEN:-ambient}" in
    token-rho)
      if [ -z "$jq_filter" ]; then
        printf '%s\n' 321 322 323
      elif [[ "$jq_filter" == *'"rikonor"'* && "$jq_filter" == *'"ideas"'* ]]; then
        echo "321"
      fi
      ;;
    token-quick) : ;;
    *)
      if [[ "$jq_filter" == *'"rikonor"'* && "$jq_filter" == *'"ideas"'* ]]; then
        echo "999"
      fi
      ;;
  esac
  exit 0
fi

if [ "${1:-}" = "api" ] && [ "${2:-}" = "-X" ] && [ "${3:-}" = "PATCH" ]; then
  case "${4:-}" in
    /user/repository_invitations/321|/user/repository_invitations/999)
      exit 0
      ;;
  esac
fi

if [ "${1:-}" = "repo" ] && [ "${2:-}" = "view" ] && [ "${3:-}" = "rikonor/ideas" ]; then
  case "${GH_TOKEN:-ambient}" in
    token-rho) echo "WRITE" ;;
    token-quick) echo "no-access" ;;
    *) echo "ADMIN" ;;
  esac
  exit 0
fi

echo "unexpected gh invocation: $*" >&2
exit 2
SH
  chmod +x "$path"
  export GH="$path"
}

setup_github_invite_mocks() {
  write_mock_secrets
  write_mock_gh
}

write_fake_github_auth_secret_tools() {
  cat > "$TMPBIN/secrets" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
store_dir="${FAKE_SECRET_STORE:?FAKE_SECRET_STORE not set}"
key_path() {
  printf '%s/%s' "$store_dir" "$(printf '%s' "$1" | tr '/' '__')"
}
case "${1:-}" in
  get)
    key="${2:?key required}"
    case "$key" in
      */github-username) printf '%s-ricon\n' "${key%%/*}" ;;
      */github-password) printf 'password-for-%s\n' "${key%%/*}" ;;
      brownie/github-pat) printf 'ghp_operator\n' ;;
      */github-pat)
        path="$(key_path "$key")"
        if [ -f "$path" ]; then cat "$path"; else printf 'ghp_old\n'; fi ;;
      */github-totp)
        path="$(key_path "$key")"
        if [ -f "$path" ]; then cat "$path"; else exit 1; fi ;;
      *)
        path="$(key_path "$key")"
        [ -f "$path" ] || exit 1
        cat "$path" ;;
    esac ;;
  set)
    key="${2:?key required}"
    path="$(key_path "$key")"
    mkdir -p "$(dirname "$path")"
    if [ "${3:-}" = "--value" ]; then
      printf '%s' "${4:-}" > "$path"
    else
      cat > "$path"
    fi
    printf '%s\n' "$key" >> "$store_dir/set-log" ;;
  totp)
    key="${2:?key required}"
    path="$(key_path "$key")"
    [ -f "$path" ] || exit 1
    if [ "${FAKE_TOTP_FAIL:-false}" = "true" ]; then
      echo "totp failed intentionally" >&2
      exit 42
    fi
    printf '123456\n' ;;
  *)
    echo "unexpected secrets command: $*" >&2
    exit 1 ;;
esac
SH
  chmod +x "$TMPBIN/secrets"
}
