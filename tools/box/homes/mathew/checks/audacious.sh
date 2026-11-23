# shellcheck shell=bash
# requires: desktop-ready
home=$(getent passwd "${BOX_USER:-$SESSION_USER}" | cut -d: -f6)
bin=$home/.nix-profile/bin
state=$home/.local/state/wallpaper-palette
stop_player() { box_user systemctl --user stop audacious-box.service || true; }
trap stop_player EXIT

pkill -USR1 hyprlock
for mode in light dark; do
  [ "$(cat "$state/mode")" = "$mode" ] || box_user "$bin/theme-mode" toggle
  box_user systemd-run --user --collect --unit=audacious-box "$bin/audacious"
  found=false
  for _ in $(seq 50); do
    if box_user env HYPRLAND_INSTANCE_SIGNATURE="$(hypr_instance)" hyprctl clients -j |
      jq -e 'any(.[]; .class == "audacious" and .title == "Audacious")' > /dev/null; then
      found=true
      break
    fi
    sleep 0.2
  done
  [ "$found" = true ] || { echo "Audacious has no matching window class" >&2; exit 1; }
  sleep 2
  box_shot 1 0
  brightness=$(magick /out/01.ppm -format '%[fx:p{w/3,h/2}.intensity*255]' info:)
  echo "$mode centre brightness: $brightness"
  if [ "$mode" = light ]; then
    awk -v n="$brightness" 'BEGIN { exit !(n > 128) }'
  else
    awk -v n="$brightness" 'BEGIN { exit !(n < 128) }'
  fi
  stop_player
done
