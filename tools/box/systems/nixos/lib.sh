# shellcheck shell=bash
# Helpers for the Hyprland session of hyprland-headless-mathew; run inside the container as its root.

# shellcheck disable=SC2034 # used by the fixtures that follow this file
SESSION_UNIT=hyprland-headless-mathew.service

hypr_instance() {
  hyprctl instances -j 2> /dev/null | jq -r '.[-1].instance // empty' 2> /dev/null || true
}

# Waits until Hyprland has an output: hyprctl answers before the headless output exists.
wait_output() {
  local i sig
  for i in $(seq 120); do
    sig=$(hypr_instance)
    if [ -n "$sig" ] && HYPRLAND_INSTANCE_SIGNATURE=$sig hyprctl monitors -j 2> /dev/null | jq -e 'length > 0' > /dev/null; then
      return 0
    fi
    sleep 0.5
  done
  echo "no Hyprland output appears in 60 s" >&2
  return 1
}

# box_shot COUNT DELAY: grim frames of HEADLESS-1 into /out (replacing the previous ones), with the pixel standard
# deviation of each. A frame that grim did not write is an error, never a leftover of an earlier run.
box_shot() {
  local count=$1 delay=$2 sig display i f sd
  sig=$(hypr_instance)
  [ -n "$sig" ] || { echo "no Hyprland instance" >&2; return 1; }
  export HYPRLAND_INSTANCE_SIGNATURE=$sig
  for display in "$XDG_RUNTIME_DIR"/wayland-[0-9]; do
    [ -S "$display" ] && break
    display=
  done
  [ -n "$display" ] || { echo "no Wayland socket" >&2; return 1; }
  export WAYLAND_DISPLAY=${display##*/}
  rm -f /out/*.ppm
  for i in $(seq "$count"); do
    f=/out/$(printf %02d "$i").ppm
    grim -t ppm -o HEADLESS-1 "$f" || return 1
    sd=$(magick "$f" -format '%[fx:standard_deviation*255]' info:) || return 1
    echo "$f stddev $sd"
    sleep "$delay"
  done
}
