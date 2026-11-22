#!/usr/bin/env bash
# networkd creates the persistent tun link; a sing-box started before it would make a link of its own, without the routing domains.
case "${1:-}" in
-h | --help)
  echo "usage: sing-box-wait-link <interface>"
  exit 0
  ;;
esac
if [ "$#" -ne 1 ]; then
  echo "sing-box-wait-link: expected one interface name" >&2
  echo "Try 'sing-box-wait-link --help' for more information." >&2
  exit 2
fi
for _ in $(seq 1 60); do
  [ -e "/sys/class/net/$1" ] && exit 0
  sleep 0.5
done
echo "sing-box-wait-link: $1 did not appear" >&2
exit 1
