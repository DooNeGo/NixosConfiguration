#!/usr/bin/env bash
# Resolve SING_BOX_VLESS_CREDENTIAL_FILE (vless://, an Amnezia vpn:// xray string or https://) into SING_BOX_VLESS_KEY_FILE.
# Every curl carries --noproxy '*': this host exports HTTP(S)_PROXY=127.0.0.1:2080.
set -euo pipefail

CRED_FILE="${SING_BOX_VLESS_CREDENTIAL_FILE:?SING_BOX_VLESS_CREDENTIAL_FILE is not set}"
KEY_FILE="${SING_BOX_VLESS_KEY_FILE:?SING_BOX_VLESS_KEY_FILE is not set}"
DECODER="${SING_BOX_DECODE_VPN:?SING_BOX_DECODE_VPN is not set}"
UA=v2rayNG/1.8.5

[ -r "$CRED_FILE" ] || { echo "vless-fetch: cannot read $CRED_FILE" >&2; exit 1; }
src=$(grep -m1 -v '^[[:space:]]*$' "$CRED_FILE" | tr -d '[:space:]')

# Extract the first vless:// line from a subscription body (base64 if needed).
extract() {
  printf '%s\n' "$1" | { base64 -d 2>/dev/null || cat; } \
    | grep -m1 -o '^vless://.*' || true
}

link=""
case "$src" in
  vless://*)
    link="$src"
    ;;
  vpn://*)
    link=$(printf '%s' "$src" | python3 -I "$DECODER" xray) \
      || { echo "vless-fetch: cannot decode the vpn:// string" >&2; exit 1; }
    ;;
  https://*|http://*)
    host=$(printf '%s' "$src" | sed -E 's#^[a-z]+://([^/:]+).*#\1#')
    port=$(printf '%s' "$src" | sed -nE 's#^http://.*#80#p; s#^https://.*#443#p')
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
    echo "vless-fetch: $CRED_FILE is neither vless://, vpn:// nor http(s):// -- refusing" >&2
    exit 1
    ;;
esac

if [ -z "$link" ]; then
  echo "vless-fetch: no vless:// link found in $CRED_FILE response" >&2
  exit 1
fi

umask 077
printf '%s\n' "$link" > "${KEY_FILE}.tmp"
mv "${KEY_FILE}.tmp" "$KEY_FILE"           # atomic: same dir, never a half-written key
echo "vless-fetch: ${KEY_FILE} updated (${#link} bytes)"
