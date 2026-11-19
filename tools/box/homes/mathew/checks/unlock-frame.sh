# shellcheck shell=bash
# requires: desktop-ready
# After the unlock the frames show the desktop: a flat frame (a lock or crossfade glitch) has a deviation below 6.
pgrep -x hyprlock > /dev/null || { echo "hyprlock is not running: nothing to unlock" >&2; exit 1; }
pkill -USR1 hyprlock
for _ in $(seq 50); do
  pgrep -x hyprlock > /dev/null || break
  sleep 0.1
done
! pgrep -x hyprlock > /dev/null || { echo "hyprlock is still running 5 s after the unlock signal" >&2; exit 1; }
frames=$(box_shot 25 0.1)
echo "$frames"
flat=$(echo "$frames" | awk '$3 < 6 { n++ } END { print n + 0 }')
[ "$flat" -eq 0 ] || { echo "$flat flat frames after the unlock" >&2; exit 1; }
