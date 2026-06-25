#!/usr/bin/env bash
# Shared helpers for fold GitHub Pages custom-domain tasks.
#
# This is a lib, not a mise task. Self-locate through common.sh rather than
# reading MISE_CONFIG_ROOT; agent shells can inherit a stale MCR.

_FOLD_GITHUB_PAGES_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091 # dynamic repo-local source
source "$_FOLD_GITHUB_PAGES_LIB_DIR/../common.sh"

GITHUB_PAGES_A_RECORDS="185.199.108.153 185.199.109.153 185.199.110.153 185.199.111.153"
GITHUB_PAGES_AAAA_RECORDS="2606:50c0:8000::153 2606:50c0:8001::153 2606:50c0:8002::153 2606:50c0:8003::153"

validate_domain() {
  local domain="$1"

  if [ -z "$domain" ]; then
    echo "ERROR: domain is required" >&2
    exit 1
  fi
  if [[ ! "$domain" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]$ ]] || [[ "$domain" != *.* ]] || [[ "$domain" == *..* ]]; then
    echo "ERROR: invalid domain: $domain" >&2
    exit 1
  fi
  if [[ "$domain" == *'*'* ]] || [[ "$domain" == *'_'* ]]; then
    echo "ERROR: wildcard and underscore domains are not supported: $domain" >&2
    exit 1
  fi
}

validate_source_path() {
  local source_path="$1"

  if [[ ! "$source_path" =~ ^/[A-Za-z0-9._/-]*$ ]]; then
    echo "ERROR: source path must start with / and contain only path-safe characters: $source_path" >&2
    exit 1
  fi
}

pages_host_for_repo() {
  local repo="$1"
  local owner

  validate_repo "$repo"
  owner="${repo%%/*}"
  printf '%s.github.io.\n' "$(lower "$owner")"
}

print_cmd_header() {
  printf '\n== %s ==\n' "$1"
}

show_pages_api() {
  local repo="$1"

  print_cmd_header "GitHub Pages"
  if ! "$GH_BIN" api "repos/$repo/pages" \
    --jq '{status,cname,html_url,https_certificate,https_enforced,source}'; then
    echo "ERROR: could not read GitHub Pages config for $repo" >&2
    return 1
  fi

  print_cmd_header "GitHub Pages health"
  if ! "$GH_BIN" api "repos/$repo/pages/health" --jq .; then
    echo "WARN: could not read GitHub Pages health for $repo" >&2
    return 1
  fi
}

show_dns_record() {
  local server="$1"
  local domain="$2"
  local type="$3"
  local label="$domain $type"

  if [ -n "$server" ]; then
    label="@$server $label"
  fi
  print_cmd_header "$label"
  if [ -n "$server" ]; then
    dig +short "@$server" "$domain" "$type"
  else
    dig +short "$domain" "$type"
  fi
}

show_dns_summary() {
  local repo="$1"
  local domain="$2"
  local www_domain="$3"
  local expected_pages_host
  local ns

  expected_pages_host="$(pages_host_for_repo "$repo")"

  print_cmd_header "expected records"
  printf 'apex A: %s\n' "$GITHUB_PAGES_A_RECORDS"
  printf 'apex AAAA: %s\n' "$GITHUB_PAGES_AAAA_RECORDS"
  printf 'www CNAME: %s -> %s\n' "$www_domain" "$expected_pages_host"

  show_dns_record "" "$domain" A
  show_dns_record "" "$domain" AAAA
  show_dns_record "" "$www_domain" CNAME
  show_dns_record "" "$domain" MX
  show_dns_record "" "$domain" TXT

  print_cmd_header "public resolver checks"
  for server in 1.1.1.1 8.8.8.8 9.9.9.9; do
    printf '\n-- @%s %s A --\n' "$server" "$domain"
    dig +short "@$server" "$domain" A
    printf -- '-- @%s %s AAAA --\n' "$server" "$domain"
    dig +short "@$server" "$domain" AAAA
    printf -- '-- @%s %s CNAME --\n' "$server" "$www_domain"
    dig +short "@$server" "$www_domain" CNAME
  done

  print_cmd_header "authoritative nameservers"
  if ! dig +short "$domain" NS | grep -q .; then
    echo "WARN: no NS records found"
    return 0
  fi

  dig +short "$domain" NS | sed 's/\.$//' | while IFS= read -r ns; do
    [ -n "$ns" ] || continue
    printf '\n-- @%s --\n' "$ns"
    dig +short "@$ns" "$domain" A
    dig +short "@$ns" "$domain" AAAA
    dig +short "@$ns" "$www_domain" CNAME
  done
}

show_http_summary() {
  local domain="$1"
  local www_domain="$2"
  local url

  print_cmd_header "HTTP/HTTPS"
  for url in "http://$domain" "https://$domain" "http://$www_domain" "https://$www_domain"; do
    printf '\n-- %s --\n' "$url"
    if ! curl -I -L --max-time 20 "$url" 2>&1 | sed -n '1,22p'; then
      echo "WARN: curl failed for $url" >&2
    fi
  done
}

show_resolve_summary() {
  local domain="$1"
  local www_domain="$2"
  local pages_ip="$3"
  local scheme
  local host

  print_cmd_header "forced GitHub Pages IP: $pages_ip"
  for scheme in http https; do
    for host in "$domain" "$www_domain"; do
      printf '\n-- %s://%s via %s --\n' "$scheme" "$host" "$pages_ip"
      if ! curl -I -L --max-time 20 \
        --resolve "$domain:80:$pages_ip" \
        --resolve "$www_domain:80:$pages_ip" \
        --resolve "$domain:443:$pages_ip" \
        --resolve "$www_domain:443:$pages_ip" \
        "$scheme://$host" 2>&1 | sed -n '1,26p'; then
        echo "WARN: forced-IP curl failed for $scheme://$host" >&2
      fi
    done
  done
}

record_present() {
  local server="$1"
  local domain="$2"
  local type="$3"
  local expected="$4"

  dig +short "@$server" "$domain" "$type" | grep -qxF "$expected"
}

check_public_a_records() {
  local domain="$1"
  local fail=0
  local server
  local ip

  for server in 1.1.1.1 8.8.8.8; do
    for ip in $GITHUB_PAGES_A_RECORDS; do
      if record_present "$server" "$domain" A "$ip"; then
        printf '✓ @%s A %s\n' "$server" "$ip"
      else
        printf '✗ @%s missing A %s\n' "$server" "$ip"
        fail=1
      fi
    done
  done

  return "$fail"
}

check_public_aaaa_records() {
  local domain="$1"
  local fail=0
  local server
  local ip

  for server in 1.1.1.1 8.8.8.8; do
    for ip in $GITHUB_PAGES_AAAA_RECORDS; do
      if record_present "$server" "$domain" AAAA "$ip"; then
        printf '✓ @%s AAAA %s\n' "$server" "$ip"
      else
        printf '✗ @%s missing AAAA %s\n' "$server" "$ip"
        fail=1
      fi
    done
  done

  return "$fail"
}

check_public_www_cname() {
  local repo="$1"
  local www_domain="$2"
  local expected
  local fail=0
  local server

  expected="$(pages_host_for_repo "$repo")"
  for server in 1.1.1.1 8.8.8.8; do
    if record_present "$server" "$www_domain" CNAME "$expected"; then
      printf '✓ @%s %s CNAME %s\n' "$server" "$www_domain" "$expected"
    else
      printf '✗ @%s %s CNAME is not %s\n' "$server" "$www_domain" "$expected"
      fail=1
    fi
  done

  return "$fail"
}

check_pages_api_ready() {
  local repo="$1"
  local domain="$2"
  local pages_json
  local health_json
  local status
  local cname
  local enforced
  local cert_state

  if ! pages_json=$("$GH_BIN" api "repos/$repo/pages"); then
    echo "✗ GitHub Pages API failed"
    return 1
  fi

  status=$(printf '%s' "$pages_json" | jq -r '.status // ""')
  cname=$(printf '%s' "$pages_json" | jq -r '.cname // ""')
  enforced=$(printf '%s' "$pages_json" | jq -r '.https_enforced // false')
  cert_state=$(printf '%s' "$pages_json" | jq -r '.https_certificate.state // ""')

  if [ "$status" = "built" ]; then
    printf '✓ Pages status built\n'
  else
    printf '✗ Pages status: %s\n' "$status"
    return 1
  fi

  if [ "$cname" = "$domain" ]; then
    printf '✓ Pages cname %s\n' "$domain"
  else
    printf '✗ Pages cname %s, expected %s\n' "$cname" "$domain"
    return 1
  fi

  if [ "$cert_state" = "approved" ]; then
    printf '✓ HTTPS certificate approved\n'
  else
    printf '✗ HTTPS certificate state: %s\n' "$cert_state"
    return 1
  fi

  if [ "$enforced" = "true" ]; then
    printf '✓ HTTPS enforced\n'
  else
    printf '✗ HTTPS is not enforced\n'
    return 1
  fi

  if ! health_json=$("$GH_BIN" api "repos/$repo/pages/health"); then
    echo "✗ Pages health API failed"
    return 1
  fi
  if [ "$health_json" = "{}" ]; then
    printf '✓ Pages health clean\n'
    return 0
  fi

  if printf '%s' "$health_json" | jq -e '
    (.domain.is_valid == true) and
    (.domain.is_served_by_pages == true) and
    (.domain.responds_to_https == true) and
    ((.alt_domain == null) or
      ((.alt_domain.is_valid == true) and
       (.alt_domain.is_served_by_pages == true) and
       (.alt_domain.responds_to_https == true)))
  ' >/dev/null; then
    printf '✓ Pages health valid for domain and alternate domain\n'
  else
    printf '✗ Pages health reports: %s\n' "$health_json"
    return 1
  fi
}

check_https_ready() {
  local domain="$1"
  local www_domain="$2"
  local fail=0
  local url

  for url in "https://$domain" "https://$www_domain"; do
    if curl -fsSI -L --max-time 20 "$url" >/dev/null; then
      printf '✓ %s responds\n' "$url"
    else
      printf '✗ %s does not respond over HTTPS\n' "$url"
      fail=1
    fi
  done

  return "$fail"
}
