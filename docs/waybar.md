# Waybar: floating islands and wallpaper palette

Files: `home-config/mathew/waybar.nix` (modules), `waybar.css` (geometry and colours by role), `random-wallpaper.nix` (palettes and the wallpaper script), `hyprland.lua` (blur rule).

## Layout

- The bar is a floating surface: `margin-top/left/right = 10` in the Waybar config, equal to `gaps_out` in `hyprland.lua`, so its edge lines up with window edges. A CSS `margin` on `window#waybar` does not move a layer-shell surface, only the config margins do.
- `window#waybar` is transparent. `.modules-left`, `.modules-center` and `.modules-right` are the three islands (`surface_container_high` at alpha 0.25 with a 1px translucent border, radius 20px, a full pill like the active workspace button).
- Dots between the right-island modules are `custom/sep#N` modules (each `#N` needs its own config entry, Waybar does not fall back to `custom/sep`).
- `output` is not set, so the bar appears on every monitor, `HEADLESS-1` (Sunshine) included.
- The clock shows `HH:MM · 15 ноября`: `locale = "ru_RU.UTF-8"` (enabled in `locale.nix`) and the `L` prefix in the format are both needed, otherwise the month is in English.
- A click on a window icon runs `hyprctl dispatch 'hl.dsp.focus({ window = "address:..." })'` (`on-click-window`). The Lua config has no legacy dispatcher names, so `focuswindow` would fail.
- A window icon in the workspace taskbar comes from a desktop entry whose file name equals the window class (`hyprctl clients`, field `class`). An app whose entry has another name shows no icon. Rider's entry in `home-config/shared/rider.nix` is named `jetbrains-rider` for this reason.
- Icons come from JetBrainsMono Nerd Font (`system-config/nixos/hyprland.nix`).

## Palette from the wallpaper

- `random-wallpaper.nix` builds `wallpaper-palettes` with `matugen` (`scheme-tonal-spot`, dark, `--source-color-index 0`, the most dominant colour of the image; `--prefer saturation` picked the most vivid one and gave an orange accent to a pink photo with a butterfly): one `<wallpaper file>.css` per image in `assets/wallpapers`, from the template `waybar-colors.tmpl.css`. Adding a wallpaper adds its palette at the next build; a failing image fails the build.
- `set-random-wallpaper.sh` copies the chosen palette to `~/.local/state/waybar/colors.css` (rename, so the bar never reads a half-written file), reloads `waybar.service` and sets the wallpaper.
- `waybar.css` imports that file and uses only the roles `surface_container_high` (island background), `surface`, `on_surface`, `on_surface_variant`, `primary`, `on_primary`. A new role needs a line in the template and in `waybar-colors-default.css`.
- `waybar.service` runs `ExecStartPre` that copies `waybar-colors-default.css` to the same path if it does not exist, so the first start has an import target.

## Modules and indicators

- Right island, in order: layout, network, sound, microphone (`custom/mic`), `custom/failed`, `idle_inhibitor`, tray. Dots separate every module, the tray included.
- `custom/failed`: the number of open `failure-notify` records, hidden when there are none (empty output hides a custom module); the dot before it is a module of its own, `custom/failed-dot`, with the same condition, so no separator is left behind and every gap is built the same way (module padding 5px, `spacing` 5px, dot padding 0). Buttons (`idle_inhibitor`, tray items) get their GTK padding, border and minimum width reset for the same reason; the offsets of `idle_inhibitor` (extra 5px on the right) and `#tray` in `waybar.css` were measured on a screenshot, not derived. A click lists the records in kitty. A failed start of `wg-quick-awg0` is recorded through `services.failure-notify` in `sing-box.nix`, so the tunnel has no indicator of its own.
- Indicator glyphs use one Pango size (`icon` helper in `waybar.nix`, `x-large`), so they match each other and the 20px tray icons; plain text stays at 13px and is raised with `rise` (`text` helper) to share the glyph's vertical centre; if the text looks too high or low, change the `rise` value.
- `custom/mic` (`waybar-mic.sh`) shows a physical microphone only (`alsa_input`/`bluez_input` source) and hides without one. It is event-driven: `pactl subscribe` reports every source change, so a mute from another app or a plugged-in headset updates the bar at once, with no polling. `audio.nix` defines the always-present virtual source `Virtual-Mumble-Microphone`, and PipeWire adds a null source when no device exists, so a source-type `wireplumber` module that follows the default source never hid. A click mutes the microphone.
- `idle_inhibitor` blocks `hypridle` until the bar restarts.
- `custom/media` (centre island) is `waybar-media.sh`: `playerctl -p playerctld --follow` prints one JSON line per player event, the title is cut at 40 characters, and a click toggles play/pause. `services.playerctld` follows the most recently active player, so a browser tab counts. Waybar's own `mpris` module has no cover art, which is why this is a custom module.
- The cover is one file, `~/.cache/waybar/media-cover`: `image-path` is static, the module reloads the file on every update and the script rewrites it (`file://` copied, `https://` fetched with a 5 s limit, removed when a track has no art; Waybar then logs a failed image load).

## Night colour

`wlsunset.nix` (Minsk coordinates, 6500 K by day, 3500 K at night) derives sunrise and sunset from latitude and longitude. `hyprsunset` has no location support, only fixed times, and with an empty config it did nothing, so it was replaced. 3500 K is a judgement call: research shows warmer light before sleep helps but gives no threshold, and the common defaults are 3400 K (f.lux evening), 3500 K (Redshift) and 4000 K (wlsunset). Change `temperature.night` to taste.

## Blur

`hl.layer_rule` for namespace `waybar` turns blur on; `ignore_alpha = 0.1` leaves the fully transparent gaps between islands unblurred.

## Troubleshooting

- Bar without icons: the font is missing (`fc-list | grep -i jetbrainsmono`).
- Bar keeps old colours after a wallpaper change: `systemctl --user status random-wallpaper waybar`; the script's reload is `try-reload-or-restart`, which sends SIGUSR2.
- Bar has no background: `~/.local/state/waybar/colors.css` is missing or has a syntax error; `journalctl --user -u waybar` shows the CSS error.
