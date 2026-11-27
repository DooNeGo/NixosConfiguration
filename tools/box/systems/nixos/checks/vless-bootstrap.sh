# shellcheck shell=bash
key=/etc/sing-box/credits-key
credential=/etc/sing-box/box-credential
bootstrap=sing-box-credits-bootstrap.service
fetch=sing-box-credits-fetch.service
timer=sing-box-credits-fetch.timer
tunnel=sing-box-credits.service

cmp "$credential" "$key"
systemctl is-active --quiet "$timer"
cleanup() {
  if [ -e "$credential.saved" ]; then mv "$credential.saved" "$credential"; fi
  systemctl start "$timer"
}
trap cleanup EXIT
systemctl stop "$timer"

inode=$(stat -c %i "$key")
systemctl start "$fetch"
test "$(stat -c %i "$key")" = "$inode"
last_fetch=$(systemctl show "$fetch" -p ExecMainStartTimestampMonotonic --value)
systemctl start "$bootstrap"
test "$(systemctl show "$bootstrap" -p ConditionResult --value)" = no
test "$(systemctl show "$fetch" -p ExecMainStartTimestampMonotonic --value)" = "$last_fetch"

# Exercise a first start while a timer refresh is also queued.
truncate -s 0 "$key"
systemctl start "$bootstrap" "$fetch"
cmp "$credential" "$key"

# The next successful timer run must start a tunnel skipped after the first fetch failed.
systemctl stop "$tunnel"
truncate -s 0 "$key"
mv "$credential" "$credential.saved"
systemctl start "$tunnel"
test "$(systemctl show "$bootstrap" -p ConditionResult --value)" = yes
systemctl is-failed --quiet "$fetch"
test "$(systemctl show "$tunnel" -p ConditionResult --value)" = no
test ! -s "$key"
mv "$credential.saved" "$credential"
systemctl start "$fetch"
cmp "$credential" "$key"
test "$(systemctl show "$bootstrap" -p ActiveState --value)" = inactive
test "$(systemctl show "$fetch" -p Result --value)" = success
if systemd-detect-virt --vm --quiet; then
  for _ in {1..50}; do
    systemctl is-active --quiet "$tunnel" && break
    sleep 0.2
  done
  systemctl is-active --quiet "$tunnel"
fi
