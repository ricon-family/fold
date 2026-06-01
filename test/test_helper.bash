fold() {
  cd "$REPO_DIR" && PATH="$TMPBIN:$PATH" mise run -q "$@" 2>"$BATS_TEST_TMPDIR/stderr"
}
export -f fold

write_fake_secret_tools() {
  cat > "$TMPBIN/secrets" <<'EOF'
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
    printf '123456\n' ;;
  *)
    echo "unexpected secrets command: $*" >&2
    exit 1 ;;
esac
EOF
  chmod +x "$TMPBIN/secrets"
}
