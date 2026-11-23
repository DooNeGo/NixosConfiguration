# shellcheck shell=bash
# The light or dark mode of the desktop: which palette of the wallpaper is active and which GTK theme and colour scheme
# the applications see. How it works: docs/hyprland.md.
#
#   theme-mode apply [light|dark]   make a mode (default: the current one) active: copy the palette of the current
#                                   wallpaper, set the GTK theme and the colour scheme, reload the consumers
#   theme-mode toggle               the other mode until the next sunrise or sunset (the daemon ends it there)
#   theme-mode auto                 the mode of the sun now, without a manual choice
#   theme-mode seed                refresh the current palette before Home Manager reloads user units
#   theme-mode reload              refresh running consumers after Home Manager reloads user units
#   theme-mode status               the state as JSON for the Waybar module
#   theme-mode daemon               follows the sun: at every sunrise and sunset applies the mode of the sun
#
# THEME_PALETTES: the palettes of every wallpaper (<wallpaper>/<mode>/<file>); THEME_STATE: the directory the consumers
# read; THEME_LAT and THEME_LON: sunwait coordinates (53.9N, 27.56E); THEME_ICONS_DARK and THEME_ICONS_LIGHT: the icon
# theme of each mode (the monochrome one is made for a dark background); THEME_SUNWAIT: sunwait, if it is not on PATH.
state=$THEME_STATE
sunwait=${THEME_SUNWAIT:-sunwait}
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"

current_mode() {
  local mode
  mode=$(cat "$state/mode" 2> /dev/null || true)
  [[ $mode == light || $mode == dark ]] && echo "$mode" || echo dark
}

# The mode of the sun now: sunwait poll exits with 2 for day (twilight included) and 3 for night.
sun_mode() {
  local rc=0
  "$sunwait" poll "$THEME_LAT" "$THEME_LON" > /dev/null || rc=$?
  case $rc in
    2) echo light ;;
    3) echo dark ;;
    *)
      echo "sunwait poll failed (exit $rc)" >&2
      return 1
      ;;
  esac
}

wallpaper_name() {
  local name
  name=$(cat "$state/wallpaper" 2> /dev/null || true)
  [[ -n $name && -d $THEME_PALETTES/$name ]] || name=$THEME_DEFAULT_WALLPAPER
  echo "$name"
}

# One file at a time by rename, so no consumer reads a half-written file.
copy_palette() {
  local mode=$1 src f
  src=$THEME_PALETTES/$(wallpaper_name)/$mode
  mkdir -p "$state"
  for f in "$src"/*; do
    cp --no-preserve=mode "$f" "$state/$(basename "$f").new"
    mv -f "$state/$(basename "$f").new" "$state/$(basename "$f")"
  done
  printf '%s\n' "$mode" > "$state/mode.new"
  mv -f "$state/mode.new" "$state/mode"
}

has_session_bus() { [[ -S $XDG_RUNTIME_DIR/bus ]]; }

# Running GTK applications follow a change of the theme name and the colour scheme at once (Nemo, Chrome); a page of
# a site reads the colour scheme as prefers-color-scheme.
set_desktop_settings() {
  local mode=$1 icons
  dconf write /org/gnome/desktop/interface/color-scheme "'prefer-$mode'"
  dconf write /org/gnome/desktop/interface/gtk-theme "'matugen-glass-$mode'"
  if [[ $mode == light ]]; then icons=$THEME_ICONS_LIGHT; else icons=$THEME_ICONS_DARK; fi
  dconf write /org/gnome/desktop/interface/icon-theme "'$icons'"
}

# Tell every running consumer of this user to read the new palette files; none of them is required to run.
# --no-block: waybar.service is ordered after random-wallpaper, which runs this; waiting for it would deadlock.
reload_consumers() {
  systemctl --user "$@" waybar.service || true
  # makoctl asks D-Bus to start mako, which fails without a session (the unit needs a Wayland display).
  if systemctl --user is-active --quiet mako.service; then makoctl reload || true; fi
  # The Nix kitty runs as a wrapped process named .kitty-wrapped.
  pkill -U "$(id -u)" -USR1 -x '\.kitty-wrapped|kitty' || true
}

apply() {
  local mode=${1:-$(current_mode)}
  [[ $mode == light || $mode == dark ]] || {
    echo "theme-mode: the mode is light or dark, not '$mode'" >&2
    return 2
  }
  copy_palette "$mode"
  if has_session_bus; then
    set_desktop_settings "$mode"
  else
    echo "No user session: the consumers and the GTK settings take the mode when they next start."
  fi
}

status() {
  local mode manual="" tip
  mode=$(current_mode)
  [[ -e $state/manual ]] && manual=manual
  if [[ -n $manual ]]; then
    tip="$mode theme, chosen by hand until the next sunrise or sunset\nRight click: back to the sun"
  else
    tip="$mode theme, by the sun\nLeft click: the other one until the next sunrise or sunset"
  fi
  jq -cn --arg alt "$mode" --arg class "$mode $manual" --arg tip "$tip" \
    '{alt: $alt, class: ($class | split(" ") | map(select(. != ""))), tooltip: $tip}'
}

change_mode() (
  local action=$1 mode
  mkdir -p "$state"
  exec 9>"$state/lock"
  flock -w 10 9
  case $action in
    apply) apply "${2:-}" ;;
    seed) apply ;;
    toggle)
      if [[ $(current_mode) == dark ]]; then mode=light; else mode=dark; fi
      : > "$state/manual"
      apply "$mode"
      ;;
    auto)
      mode=$(sun_mode)
      rm -f "$state/manual"
      apply "$mode"
      ;;
  esac
)

case ${1:-status} in
  apply | toggle | auto)
    change_mode "$@"
    if has_session_bus; then reload_consumers --no-block try-reload-or-restart; fi
    ;;
  seed) change_mode seed ;;
  reload) if has_session_bus; then reload_consumers try-restart; fi ;;
  status) status ;;
  daemon)
    # `sunwait wait` sleeps until the next sunrise or sunset and exits with an error when it has nothing to wait for
    # (polar day): then check again later. The poll after it must see the new side of the horizon.
    while true; do
      "$sunwait" wait "$THEME_LAT" "$THEME_LON" || sleep 300
      sleep 5
      until "$0" auto; do sleep 60; done
    done
    ;;
  *)
    echo "usage: theme-mode apply [light|dark] | toggle | auto | seed | reload | status | daemon" >&2
    exit 2
    ;;
esac
