#!/usr/bin/env bash
# Waybar microphone indicator for a physical microphone only: the virtual sources of audio.nix (Mumble, null source)
# always exist, so a source-type wireplumber module never hides.
# Runs for the life of the module and prints one JSON line when the state changes, an empty line (the module hides)
# without an alsa_input or bluez_input source. `pactl subscribe` delivers the events, so a mute from any app,
# a plugged-in headset or a removed one updates the bar at once. `waybar-mic toggle` mutes or unmutes that source.
# WAYBAR_MIC_GLYPH_ON / _OFF are the glyphs and WAYBAR_MIC_ICON_SIZE the Pango size they are wrapped in.
physical_source() {
  local list name
  list=$(pactl list short sources)
  while read -r _ name _; do
    if [[ $name == alsa_input* || $name == bluez_input* ]]; then
      echo "$name"
      return
    fi
  done <<< "$list"
}

span() { printf '<span font_size="%s">%s</span>' "$WAYBAR_MIC_ICON_SIZE" "$1"; }

state() {
  local name glyph class
  name=$(physical_source)
  [[ -n $name ]] || return 0
  if [[ $(pactl get-source-mute "$name") == *yes* ]]; then
    glyph=$WAYBAR_MIC_GLYPH_OFF class=muted
  else
    glyph=$WAYBAR_MIC_GLYPH_ON class=on
  fi
  jq -cn --arg text "$(span "$glyph")" --arg class "$class" '{text: $text, class: $class, tooltip: "Microphone \($class)"}'
}

if [[ ${1:-} == toggle ]]; then
  name=$(physical_source)
  [[ -n $name ]] || exit 0
  exec pactl set-source-mute "$name" toggle
fi

last=$'\001'
refresh() {
  local out
  out=$(state)
  if [[ $out != "$last" ]]; then
    last=$out
    echo "$out"
  fi
}

while true; do
  refresh
  # Process substitution keeps `last` in this shell; the loop ends when pactl exits and is started again.
  while read -r line; do
    case $line in
      *" source "* | *" server"*) refresh ;;
    esac
  done < <(pactl subscribe 2> /dev/null)
  sleep 2
done
