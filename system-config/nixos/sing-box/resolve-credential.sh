#!/usr/bin/env bash
# Resolve SING_BOX_CREDENTIAL_FILE (vless:// or https://) into SING_BOX_KEY_FILE.
# Every curl carries --noproxy '*': this host exports HTTP(S)_PROXY=127.0.0.1:2080.
set -euo pipefail

CRED_FILE="${SING_BOX_CREDENTIAL_FILE:?SING_BOX_CREDENTIAL_FILE is not set}"
KEY_FILE="${SING_BOX_KEY_FILE:?SING_BOX_KEY_FILE is not set}"
UA=v2rayNG/1.8.5

[ -r "$CRED_FILE" ] || { echo "resolve-credential: cannot read $CRED_FILE" >&2; exit 1; }
src=$(grep -m1 -v '^[[:space:]]*$' "$CRED_FILE" | tr -d '\r\n')

# Extract the first vless:// line from a subscription body (base64 if needed) --
# byte-for-byte the pipeline from the former fetch-subscription.sh.
extract() {
  printf '%s\n' "$1" | { base64 -d 2>/dev/null || cat; } \
    | grep -m1 -o '^vless://.*' || true
}

link=""
case "$src" in
  vless://*)
    link="$src"
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
        echo "resolve-credential: DoH resolve failed" >&2
        exit 1
      fi
      echo "resolve-credential: DNS failed, using DoH fallback" >&2
      fetch --resolve "${host}:${port}:${ip}" "$src"
    })
    link=$(extract "$body")
    ;;
  *)
    echo "resolve-credential: $CRED_FILE is neither vless:// nor http(s):// -- refusing" >&2
    exit 1
    ;;
esac

if [ -z "$link" ]; then
  echo "resolve-credential: no vless:// link found in $CRED_FILE response" >&2
  exit 1
fi

umask 077
printf '%s\n' "$link" > "${KEY_FILE}.tmp"
mv "${KEY_FILE}.tmp" "$KEY_FILE"           # atomic: same dir, never a half-written key
echo "resolve-credential: ${KEY_FILE} updated (${#link} bytes)"
