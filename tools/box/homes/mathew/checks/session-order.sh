# shellcheck shell=bash
# requires: desktop-ready (shared)
# hyprlock-initial locks a desktop that has drawn: it starts after hyprpaper and waybar.
ts() { box_user systemctl --user show -p ActiveEnterTimestampMonotonic --value "$1"; }
lock=$(ts hyprlock-initial)
for unit in hyprpaper waybar; do
  other=$(ts "$unit")
  echo "$unit $other, hyprlock-initial $lock"
  [ "$other" -gt 0 ] || { echo "$unit never started" >&2; exit 1; }
  [ "$lock" -gt "$other" ] || { echo "hyprlock-initial started before $unit" >&2; exit 1; }
done
