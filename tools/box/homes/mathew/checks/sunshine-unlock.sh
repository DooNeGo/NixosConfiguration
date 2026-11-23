# shellcheck shell=bash
# backends: container
# requires: desktop-ready
box_user systemctl --user is-active --quiet sunshine.service || { echo "Sunshine did not start" >&2; exit 1; }
pkill -USR1 hyprlock
for _ in $(seq 50); do
  pgrep -x hyprlock > /dev/null || break
  sleep 0.1
done
! pgrep -x hyprlock > /dev/null || { echo "hyprlock did not exit" >&2; exit 1; }
box_user systemctl --user is-active --quiet sunshine.service || { echo "Sunshine stopped after unlock" >&2; exit 1; }
echo "Sunshine stays active after unlock"
