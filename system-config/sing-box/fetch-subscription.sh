#!/usr/bin/env bash
# Fetch the VLESS subscription and write the first vless:// link into
# /etc/sing-box/vless-key (mode 0600, atomic replace).
#
# The subscription URL lives in /etc/sing-box/subscription-url (root 0600,
# created manually once). vless-key is regenerated on every run, so key
# rotation by the provider is handled automatically.
#
# DNS caveat: the subscription host may be unresolvable via the router/ISP
# DNS (observed: instant gaierror inside sandboxed units). Fallback: resolve
# via DoH against 1.1.1.1 (by IP, no DNS needed) and fetch with --resolve.
set -euo pipefail

URL_FILE=/etc/sing-box/subscription-url
KEY_FILE=/etc/sing-box/vless-key
UA=v2rayNG/1.8.5

url=$(cat "$URL_FILE")
host=$(printf '%s' "$url" | sed -E 's#^[a-z]+://([^/:]+).*#\1#')

fetch() { curl -sfL --noproxy '*' -A "$UA" --max-time 30 "$@"; }

body=$(fetch "$url" || {
  # DoH fallback: resolve A record via 1.1.1.1 (talked to by IP).
  ip=$(curl -sfL --noproxy '*' -H 'accept: application/dns-json' --max-time 15 \
        "https://1.1.1.1/dns-query?name=${host}&type=A" \
      | sed -n 's/.*"data":"\([0-9.]*\)".*/\1/p' | head -1)
  if [ -z "$ip" ]; then
    echo "sing-box-subscription: DoH resolve failed for ${host}" >&2
    exit 1
  fi
  echo "sing-box-subscription: DNS failed for ${host}, using DoH ip ${ip}" >&2
  fetch --resolve "${host}:443:${ip}" "$url"
})

link=$(printf '%s\n' "$body" | { base64 -d 2>/dev/null || cat; } \
       | grep -m1 -o '^vless://.*' || true)
if [ -z "$link" ]; then
  echo "sing-box-subscription: no vless:// link found in subscription response" >&2
  exit 1
fi

umask 077
printf '%s\n' "$link" > "${KEY_FILE}.tmp"
mv "${KEY_FILE}.tmp" "$KEY_FILE"
echo "sing-box-subscription: vless-key updated (${#link} bytes)"