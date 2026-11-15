#!/usr/bin/env bash
# Feeds the waybar media module: one JSON line per player event, an empty line when nothing plays.
# WAYBAR_MEDIA_COVER is the file the module's static image-path points at, so the cover is rewritten in place.
max_title=40

fetch_cover() {
  local url=$1 tmp="$WAYBAR_MEDIA_COVER.tmp"
  case $url in
    file://*)
      local path=${url#file://}
      cp -- "$(printf '%b' "${path//\%/\\x}")" "$tmp"
      ;;
    http://* | https://*) curl -sfL -m 5 -o "$tmp" -- "$url" ;;
    *) return 1 ;;
  esac && mv -f -- "$tmp" "$WAYBAR_MEDIA_COVER"
}

emit() {
  local status=$1 title=$2
  if ((${#title} > max_title)); then
    title="${title:0:max_title-1}…"
  fi
  [[ $status == Playing ]] || title="󰏤 $title"
  jq -cn --arg text "$title" --arg class "${status,,}" '{text: $text, class: $class, tooltip: $text}'
}

mkdir -p "$(dirname "$WAYBAR_MEDIA_COVER")"
last_art=""

while true; do
  # '|' is not whitespace, so an empty artUrl keeps its field; the title goes last because it may contain '|'.
  playerctl -p playerctld --follow metadata --format '{{status}}|{{mpris:artUrl}}|{{title}}' 2> /dev/null |
    while IFS='|' read -r status art title; do
      if [[ -z $status || $status == Stopped || -z $title ]]; then
        echo
        continue
      fi
      if [[ $art != "$last_art" ]]; then
        last_art=$art
        fetch_cover "$art" || rm -f -- "$WAYBAR_MEDIA_COVER"
      fi
      emit "$status" "$title"
    done || true
  echo
  sleep 2
done
