#!/usr/bin/env bash
# Home-local provisioning policy; Emails owns account config serialization.

homes_email_fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

homes_email_private_file() {
  local file="$1" metadata
  [ -f "$file" ] && [ ! -L "$file" ] || homes_email_fail 'email config must be a regular file, not a symlink'
  if metadata=$(stat -f '%u:%Lp:%l' "$file" 2>/dev/null); then
    :
  else
    metadata=$(stat -c '%u:%a:%h' "$file")
  fi
  [ "$metadata" = "$(id -u):600:1" ] || homes_email_fail 'email config must be owned, mode 0600 and singly linked'
}

homes_email_check_signer() {
  local signer="$1" metadata
  if ! metadata=$("$GPG_BIN" --batch --with-colons --list-secret-keys -- "$signer" 2>/dev/null); then
    homes_email_fail "missing email signing key: $signer"
  fi
  if ! printf '%s\n' "$metadata" | awk -F: -v signer="$signer" -v now="$(date +%s)" '
    $1 == "sec" { primary_ok = ($2 !~ /[red]/ && ($7 == "" || $7 == 0 || $7 > now)) }
    $1 == "sec" || $1 == "ssb" {
      usable = primary_ok && $2 !~ /[red]/ && ($7 == "" || $7 == 0 || $7 > now) && index($12, "s") && $15 != "#"
    }
    $1 == "fpr" && $10 == signer && usable { found = 1 }
    END { exit !found }
  '; then
    homes_email_fail "exact usable email signing key unavailable: $signer"
  fi
}

homes_email_render_account() {
  local record="$1" config="$2" downloads="$3" label default
  label=$(printf '%s' "$record" | jq -r '.label')
  default=$(printf '%s' "$record" | jq -r '.default')
  local args=(account:setup "$label"
    --address "$(printf '%s' "$record" | jq -r '.address')"
    --display-name "$(printf '%s' "$record" | jq -r '.display_name')"
    --imap-host "$(printf '%s' "$record" | jq -r '.imap.host')"
    --imap-port "$(printf '%s' "$record" | jq -r '.imap.port')"
    --imap-encryption "$(printf '%s' "$record" | jq -r '.imap.encryption')"
    --smtp-host "$(printf '%s' "$record" | jq -r '.smtp.host')"
    --smtp-port "$(printf '%s' "$record" | jq -r '.smtp.port')"
    --smtp-encryption "$(printf '%s' "$record" | jq -r '.smtp.encryption')"
    --gpg-fingerprint "$(printf '%s' "$record" | jq -r '.signer')"
    --downloads-dir "$downloads/$label" --credentials-stdin)
  [ "$default" != true ] || args+=(--set-default)

  if ! printf '%s' "$record" | jq '{imap: (.imap | {username, password}), smtp: (.smtp | {username, password})}' |
    env -u __MISE_DIFF -u HIMALAYA_CONFIG EMAILS_CONFIG="$config" \
      "$EMAILS_BIN" "${args[@]}" >"$STAGING/setup.log" 2>&1; then
    homes_email_fail "Emails account setup failed for $label; requires independent transport credentials and fingerprint support"
  fi
}

homes_email_provision() {
  local home="$1" bundle="$2" config
  config="$home/.emails/himalaya.toml"
  local git_dir exclude record records existing=false
  [ -d "$home/.git" ] || homes_email_fail "home is not a Git repository: $home"
  [ ! -L "$home/.emails" ] || homes_email_fail 'refusing a symlinked email directory'
  if [ -e "$home/.emails" ]; then
    [ -d "$home/.emails" ] && [ -O "$home/.emails" ] || homes_email_fail 'email directory must be owned by the current user'
  fi
  if [ -e "$config" ] || [ -L "$config" ]; then
    homes_email_private_file "$config"
    existing=true
  fi
  if "$GIT_BIN" -C "$home" ls-files --error-unmatch -- .emails/himalaya.toml >/dev/null 2>&1; then
    homes_email_fail 'refusing a tracked email config'
  fi

  git_dir=$("$GIT_BIN" -C "$home" rev-parse --absolute-git-dir)
  exclude="$git_dir/info/exclude"
  mkdir -p "$home/.emails" "$(dirname "$exclude")"
  chmod 700 "$home/.emails"
  if ! grep -Fxq '/.emails/' "$exclude" 2>/dev/null; then
    printf '\n/.emails/\n' >> "$exclude"
  fi
  "$GIT_BIN" -C "$home" check-ignore -q -- .emails/himalaya.toml || homes_email_fail 'email config is not ignored'

  STAGING=$(mktemp -d "$home/.emails/.setup.XXXXXX")
  trap 'rm -rf "$STAGING"' EXIT
  records=$(printf '%s' "$bundle" | jq -c '.[]')
  while IFS= read -r record; do
    homes_email_render_account "$record" "$STAGING/himalaya.toml" "$home/.emails/downloads"
  done <<< "$records"
  homes_email_private_file "$STAGING/himalaya.toml"

  if $existing; then
    homes_email_private_file "$config"
    cmp -s "$STAGING/himalaya.toml" "$config" || homes_email_fail 'existing email config differs from the declared persona; preserved unchanged'
    printf '\nEmail already ready: %s\n' "$config"
  else
    # Link into the parent: any existing basename, including a directory, is a collision.
    ln "$STAGING/himalaya.toml" "$home/.emails/" || homes_email_fail 'email destination appeared during setup; preserved'
    rm "$STAGING/himalaya.toml"
    homes_email_private_file "$config"
    printf '\nEmail ready: %s\n' "$config"
  fi
}
