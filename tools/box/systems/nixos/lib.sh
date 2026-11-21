# shellcheck shell=bash
# Helpers for the Hyprland session of hyprland-headless-mathew; run inside the system as its root. A command of the
# session user goes through box_user (`backends/lib.sh`).

# shellcheck disable=SC2034 # used by the fixtures that follow this file
SESSION_UNIT=hyprland-headless-mathew.service
# shellcheck disable=SC2034 # used by box_user when no home names the user
SESSION_USER=mathew

hypr_instance() {
  box_user hyprctl instances -j 2> /dev/null | jq -r '.[-1].instance // empty' 2> /dev/null || true
}

# Waits until Hyprland has an output: hyprctl answers before the headless output exists.
wait_output() {
  local i sig
  for i in $(seq 120); do
    sig=$(hypr_instance)
    if [ -n "$sig" ] && box_user env HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl monitors -j 2> /dev/null | jq -e 'length > 0' > /dev/null; then
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
  local count=$1 delay=$2 sig display runtime i f sd
  sig=$(hypr_instance)
  [ -n "$sig" ] || { echo "no Hyprland instance" >&2; return 1; }
  runtime=/run/user/$(box_user id -u)
  for display in "$runtime"/wayland-[0-9]; do
    [ -S "$display" ] && break
    display=
  done
  [ -n "$display" ] || { echo "no Wayland socket" >&2; return 1; }
  rm -f /out/*.ppm
  for i in $(seq "$count"); do
    f=/out/$(printf %02d "$i").ppm
    # grim writes to stdout and this shell to the file: the session user needs no access to /out
    box_user env HYPRLAND_INSTANCE_SIGNATURE="$sig" WAYLAND_DISPLAY="${display##*/}" grim -t ppm -o HEADLESS-1 - > "$f" || return 1
    sd=$(magick "$f" -format '%[fx:standard_deviation*255]' info:) || return 1
    echo "$f stddev $sd"
    sleep "$delay"
  done
}
