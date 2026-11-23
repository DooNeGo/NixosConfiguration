#!/usr/bin/env bash
# Screenshots of the desktop of `mathew` in the box, for every light/dark mode on a dark and a bright wallpaper: the
# bar, kitty with htop, Nemo and a notification on one frame, the launcher on a second one.
#
#   tools/box/homes/mathew/shots.sh OUTDIR [WALLPAPER...]   # PNGs <mode>-<wallpaper>-{desktop,rofi}.png in OUTDIR
#
# Without WALLPAPER it takes the darkest and the brightest image of assets/wallpapers. It brings up its own instance
# (`box up`), unlocks the session and takes it down at the end (KEEP=1 leaves it running). The same file runs inside
# the box: the host copies it into the output directory of the instance and `box exec` sources it for each scene.
set -euo pipefail

name=shots-mathew
home_path=/home/mathew/.local/state/nix/profiles/home-manager/home-path
palette_state=/home/mathew/.local/state/wallpaper-palette

# --- inside the box (sourced by `box exec`, which defines box_user, box_shot and hypr_instance) -----------------------

# Runs a command as the session user with the Wayland, Hyprland and GTK environment of the session.
as_user() {
  box_user env HYPRLAND_INSTANCE_SIGNATURE="$(hypr_instance)" WAYLAND_DISPLAY=wayland-1 \
    XDG_DATA_DIRS="$home_path/share:/run/current-system/sw/share" PATH="$home_path/bin:/run/current-system/sw/bin" "$@"
}

wall_dir() {
  grep -o '/nix/store/[^ ]*-wallpapers' /home/mathew/.local/bin/set-random-wallpaper.sh | head -1
}

# Prints the darkest and the brightest wallpaper by mean luminance.
pick_walls() {
  local f
  for f in "$(wall_dir)"/*; do
    echo "$(magick "$f" -resize 64x64 -colorspace Gray -format '%[fx:mean]' info:) ${f##*/}"
  done | sort -n | sed -n '1p;$p' | cut -d' ' -f2
}

# One scene: wallpaper and mode, then the desktop frame and the launcher frame into /out/shots.
scene() {
  local mode=$1 wall=$2 tag=$3
  mkdir -p /out/shots
  as_user pkill -x kitty || true
  as_user pkill -x nemo || true
  as_user pkill -x rofi || true
  echo "$wall" > "$palette_state/wallpaper"
  chown mathew: "$palette_state/wallpaper"
  as_user theme-mode apply "$mode" > /dev/null
  as_user hyprctl hyprpaper wallpaper ",$(wall_dir)/$wall" > /dev/null
  pgrep -x mako > /dev/null || as_user setsid -f mako
  as_user setsid -f kitty htop
  sleep 2
  as_user setsid -f nemo /etc
  sleep 5
  as_user notify-send -t 30000 "Build finished" "home-manager switch completed in 41 s"
  sleep 2
  box_shot 1 0 > /dev/null
  mv /out/01.ppm "/out/shots/$tag-desktop.ppm"
  as_user setsid -f rofi -show drun
  sleep 2
  box_shot 1 0 > /dev/null
  mv /out/01.ppm "/out/shots/$tag-rofi.ppm"
  as_user pkill -x rofi || true
}

[ "${BASH_SOURCE[0]}" = "$0" ] || return 0

# --- on the host ------------------------------------------------------------------------------------------------------

out=${1:?usage: $0 OUTDIR [WALLPAPER...]}
shift
repo=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
box=$repo/tools/box/box
inst_out=${XDG_STATE_HOME:-$HOME/.local/state}/box/$name/out
mkdir -p "$out"

"$box" up --name "$name" --system nixos --home mathew > /dev/null
[ "${KEEP:-0}" = 1 ] || trap '"$box" down --name "$name" > /dev/null 2>&1' EXIT
"$box" fixture --name "$name" desktop-ready setup > /dev/null
"$box" exec --name "$name" 'pkill -USR1 hyprlock; sleep 3'
cp "$0" "$inst_out/shots-lib.sh"
in_box() {
  local command
  printf -v command ' %q' "$@"
  "$box" exec --name "$name" ". /out/shots-lib.sh;$command"
}

if [ $# -eq 0 ]; then
  mapfile -t walls < <(in_box pick_walls)
else
  walls=("$@")
fi

rm -rf "$inst_out/shots"
for wall in "${walls[@]}"; do
  for mode in dark light; do
    echo "$mode on $wall"
    in_box scene "$mode" "$wall" "$mode-${wall%.*}"
  done
done

for f in "$inst_out"/shots/*.ppm; do
  ffmpeg -loglevel error -y -i "$f" "$out/$(basename "${f%.ppm}").png"
done
ls "$out"
