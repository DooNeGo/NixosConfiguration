#!/usr/bin/env bash
# Resolve SING_BOX_VLESS_CREDENTIAL_FILE (vless://, an Amnezia vpn:// xray string or https://) into SING_BOX_VLESS_KEY_FILE.
# Every curl carries --noproxy '*' to avoid a loop if a proxy is configured externally.
set -euo pipefail

CRED_FILE="${SING_BOX_VLESS_CREDENTIAL_FILE:?SING_BOX_VLESS_CREDENTIAL_FILE is not set}"
KEY_FILE="${SING_BOX_VLESS_KEY_FILE:?SING_BOX_VLESS_KEY_FILE is not set}"
DECODER="${SING_BOX_DECODE_VPN:?SING_BOX_DECODE_VPN is not set}"
UA=v2rayNG/1.8.5

[ -r "$CRED_FILE" ] || { echo "vless-fetch: cannot read $CRED_FILE" >&2; exit 1; }
decoded=$(python3 -I "$DECODER" xray --passthrough < "$CRED_FILE") \
  || { echo "vless-fetch: cannot decode the vpn:// string" >&2; exit 1; }
src=$(printf '%s\n' "$decoded" | grep -m1 -v '^[[:space:]]*$' | tr -d '[:space:]' || true)

# Extract the first vless:// line from a subscription body (base64 if needed).
extract() {
  local body
  body=$(printf '%s\n' "$1" | base64 -d 2>/dev/null) || body=$1
  printf '%s\n' "$body" | grep -m1 -o '^vless://.*' || true
}

link=""
case "$src" in
  vless://*)
    link="$src"
    ;;
  https://*|http://*)
    host=$(printf '%s' "$src" | sed -E 's#^[a-z]+://([^/:]+).*#\1#')
    port=$(python3 -c 'import sys, urllib.parse; u = urllib.parse.urlsplit(sys.argv[1]); print(u.port or (443 if u.scheme == "https" else 80))' "$src")
    # fetch() -- the --noproxy '*' on EVERY request is the loop guard.
    fetch() { curl -sfL --noproxy '*' -A "$UA" --max-time 30 "$@"; }
    body=$(fetch "$src" || {
      # DoH fallback: resolve A via 1.1.1.1 (talked to by IP; no DNS needed).
      ip=$(curl -sfL --noproxy '*' -H 'accept: application/dns-json' --max-time 15 \
            "https://1.1.1.1/dns-query?name=${host}&type=A" \
          | sed -n 's/.*"data":"\([0-9.]*\)".*/\1/p' | head -1)
      if [ -z "$ip" ]; then
        echo "vless-fetch: DoH resolve failed" >&2
        exit 1
      fi
      echo "vless-fetch: DNS failed, using DoH fallback" >&2
      fetch --resolve "${host}:${port}:${ip}" "$src"
    })
    link=$(extract "$body")
    ;;
  *)
    echo "vless-fetch: $CRED_FILE is neither vless://, vpn:// (xray) nor http(s):// -- refusing" >&2
    exit 1
    ;;
esac

if [ -z "$link" ]; then
  echo "vless-fetch: no vless:// link found in $CRED_FILE response" >&2
  exit 1
fi

printf '%s\n' "$link" | python3 -I "${SING_BOX_VLESS_PARSER:?SING_BOX_VLESS_PARSER is not set}" \
  || { echo "vless-fetch: invalid or unsupported VLESS link" >&2; exit 1; }

umask 077
printf '%s\n' "$link" > "${KEY_FILE}.tmp"
if cmp -s "${KEY_FILE}.tmp" "$KEY_FILE"; then
  rm "${KEY_FILE}.tmp"
else
  if [ -n "${SING_BOX_VLESS_SERVICE:-}" ]; then
    : > "${KEY_FILE}.restart-pending"
  fi
  mv "${KEY_FILE}.tmp" "$KEY_FILE"
  echo "vless-fetch: ${KEY_FILE} updated (${#link} bytes)"
fi
if [ -e "${KEY_FILE}.restart-pending" ] && [ -n "${SING_BOX_VLESS_SERVICE:-}" ]; then
  systemctl try-restart --no-block "$SING_BOX_VLESS_SERVICE"
  rm "${KEY_FILE}.restart-pending"
fi
