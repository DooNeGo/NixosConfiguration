#!/usr/bin/env bash
# Turn the server-issued AmneziaWG .conf or Amnezia vpn:// string (SING_BOX_AWG_SOURCE_FILE,
# kept verbatim in agenix; a vpn:// string is decoded by SING_BOX_DECODE_VPN)
# into the runtime config that awg-quick gets (SING_BOX_AWG_OUT_FILE):
#   * DNS is dropped        -- awg-quick would make it the system resolver;
#   * hooks are dropped     -- a third-party file must not run commands as root;
#   * Table = SING_BOX_AWG_TABLE -- routes go to a private table, main stays intact;
#   * Address: IPv4 only; AllowedIPs = 0.0.0.0/0 (the tunnel is IPv4-only).
# The tunnel address is published to SING_BOX_AWG_ADDR_FILE (not a secret) for the
# policy rule and for sing-box's inet4_bind_address.
set -euo pipefail

SRC="${SING_BOX_AWG_SOURCE_FILE:?SING_BOX_AWG_SOURCE_FILE is not set}"
OUT="${SING_BOX_AWG_OUT_FILE:?SING_BOX_AWG_OUT_FILE is not set}"
ADDR_OUT="${SING_BOX_AWG_ADDR_FILE:?SING_BOX_AWG_ADDR_FILE is not set}"
TABLE="${SING_BOX_AWG_TABLE:?SING_BOX_AWG_TABLE is not set}"
DECODER="${SING_BOX_DECODE_VPN:?SING_BOX_DECODE_VPN is not set}"

die() { echo "awg-prepare: $*" >&2; exit 1; }

[ -r "$SRC" ] || die "cannot read $SRC"
case "$TABLE" in ''|*[!0-9]*) die "SING_BOX_AWG_TABLE must be a number, got '$TABLE'" ;; esac

text=$(python3 -I "$DECODER" awg --passthrough < "$SRC") || die "cannot decode the vpn:// string"
conf=$(printf '%s\n' "$text" | tr -d '\r' | sed 's/[[:space:]]*#.*$//')   # awg-quick ignores trailing comments too

count() { printf '%s\n' "$conf" | grep -ciE "$1" || true; }
[ "$(count '^[[:space:]]*\[interface\]')" = 1 ] || die "expected exactly one [Interface] section"
[ "$(count '^[[:space:]]*\[peer\]')" = 1 ] || die "expected exactly one [Peer] section"
[ "$(count '^[[:space:]]*allowedips[[:space:]]*=')" = 1 ] || die "expected exactly one AllowedIPs line"

# First IPv4 entry of [Interface] Address (may be a comma list with IPv6).
cidr=$(printf '%s\n' "$conf" | awk '
  /^[ \t]*\[/ { sec = tolower($0); gsub(/[ \t\[\]]/, "", sec); next }
  sec == "interface" {
    k = $0; sub(/[ \t]*=.*/, "", k); gsub(/^[ \t]+/, "", k)
    if (tolower(k) != "address") next
    v = $0; sub(/^[^=]*=/, "", v)
    n = split(v, parts, ",")
    for (i = 1; i <= n; i++) {
      a = parts[i]; gsub(/[ \t]/, "", a)
      if (a ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(\/[0-9]+)?$/) { print a; exit }
    }
  }')
[ -n "$cidr" ] || die "no IPv4 Address in [Interface]"
case "$cidr" in */*) ;; *) cidr="$cidr/32" ;; esac
addr="${cidr%/*}"

umask 077
printf '%s\n' "$conf" | awk -v table="$TABLE" -v cidr="$cidr" '
  function key(line,   k) {
    k = line; sub(/[ \t]*=.*/, "", k); gsub(/^[ \t]+/, "", k); return tolower(k)
  }
  /^[ \t]*\[/ {
    sec = tolower($0); gsub(/[ \t\[\]]/, "", sec)
    print
    if (sec == "interface") { print "Table = " table; print "Address = " cidr }
    next
  }
  sec == "interface" && key($0) ~ /^(dns|table|address|preup|postup|predown|postdown|saveconfig)$/ { next }
  sec == "peer" && key($0) == "allowedips" { print "AllowedIPs = 0.0.0.0/0"; next }
  { print }
' > "${OUT}.tmp"
mv "${OUT}.tmp" "$OUT"                      # atomic, 0600 root

umask 022
printf '%s\n' "$addr" > "${ADDR_OUT}.tmp"
mv "${ADDR_OUT}.tmp" "$ADDR_OUT"            # 0644: read by the sing-box user

echo "awg-prepare: ${OUT} written (address ${addr}, table ${TABLE})"

