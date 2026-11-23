# shellcheck shell=bash
# requires: desktop-ready (shared)
# theme-mode follows the sun: with a stub of sunwait that answers day or night, the automatic mode, the colour scheme and
# GTK theme in dconf and the palette in the state directory switch together, a manual toggle is marked and `auto` ends it.
user=${BOX_USER:-$SESSION_USER}
home=$(getent passwd "$user" | cut -d: -f6)
bin=$home/.local/state/nix/profiles/home-manager/home-path/bin/theme-mode
state=$home/.local/state/wallpaper-palette
stub=/tmp/sunwait-stub
cat > "$stub" << 'STUB'
#!/bin/sh
# What sunwait does for poll: exit 2 for day and 3 for night. The answer is the content of /tmp/sun.
[ "$1" = poll ] || exit 0
[ "$(cat /tmp/sun)" = day ] && exit 2
exit 3
STUB
chmod 755 "$stub"

tm() { box_user env THEME_SUNWAIT="$stub" "$bin" "$@"; }
fail() {
  echo "$*" >&2
  exit 1
}
expect() { # expect MODE SCHEME: what the state and dconf say after a change
  local mode=$1 scheme=$2 got surface
  [ "$(cat "$state/mode")" = "$mode" ] || fail "mode file is '$(cat "$state/mode")', wanted $mode"
  got=$(box_user dconf read /org/gnome/desktop/interface/color-scheme)
  [ "$got" = "'prefer-$scheme'" ] || fail "color-scheme is $got, wanted prefer-$scheme"
  got=$(box_user dconf read /org/gnome/desktop/interface/gtk-theme)
  [ "$got" = "'matugen-glass-$mode'" ] || fail "gtk-theme is $got, wanted matugen-glass-$mode"
  surface=$(sed -n 's/^@define-color surface #\([0-9a-f]\{2\}\).*/\1/p' "$state/waybar.css")
  # The red channel of the background: below 0x80 in a dark palette, above it in a light one.
  [ -n "$surface" ] || fail "waybar.css has no surface colour"
  if [ "$mode" = light ]; then [ $((16#$surface)) -ge 128 ] || fail "the surface of the $mode palette is dark"; else [ $((16#$surface)) -lt 128 ] || fail "the surface of the $mode palette is light"; fi
  [ -s "$state/KvMatugen.svg" ] && [ -s "$state/KvMatugen.kvconfig" ] || fail "the Kvantum theme is missing"
  echo "ok $mode"
}

echo day > /tmp/sun
tm auto
expect light light
[ ! -e "$state/manual" ] || fail "auto left a manual choice"

echo night > /tmp/sun
tm auto
expect dark dark

tm toggle
expect light light
[ -e "$state/manual" ] || fail "toggle did not mark the choice as manual"
tm status | jq -e '.alt == "light" and (.class | index("manual"))' > /dev/null || fail "status does not show the manual light mode: $(tm status)"

tm auto
expect dark dark
tm status | jq -e '.alt == "dark" and (.class | index("manual") | not)' > /dev/null || fail "status still shows a manual choice: $(tm status)"

# Home Manager may run without the graphical session environment.
invocation() { box_user systemctl --user show -p InvocationID --value waybar.service; }
before=$(invocation)
box_user env -u XDG_RUNTIME_DIR -u DBUS_SESSION_BUS_ADDRESS "$bin" seed
expect dark dark
[ "$(invocation)" = "$before" ] || fail "seed restarted Waybar before the user unit transition"
box_user env -u XDG_RUNTIME_DIR -u DBUS_SESSION_BUS_ADDRESS "$bin" reload
after=$(invocation)
[ -n "$after" ] && [ "$after" != "$before" ] || fail "reload did not restart Waybar"
