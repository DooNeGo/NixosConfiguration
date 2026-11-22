# Waybar: floating islands and wallpaper palette

Files: `home-config/mathew/waybar.nix` (modules), `waybar.css` (geometry and colours by role), `wallpaper/` (palettes and the wallpaper script), `hyprland/rules.lua` (blur rule).

## Layout

- The bar is a floating surface: `margin-top/left/right = 10` in the Waybar config, equal to `gaps_out` in `hyprland/settings.lua`, so its edge lines up with window edges. A CSS `margin` on `window#waybar` does not move a layer-shell surface, only the config margins do.
- `window#waybar` is transparent. `.modules-left`, `.modules-center` and `.modules-right` are the three islands (the glass fill and border and the panel radius of `style/`, `docs/hyprland.md`); the workspace buttons inside use the smaller inner radius.
- Dots between the right-island modules are `custom/sep#N` modules (each `#N` needs its own config entry, Waybar does not fall back to `custom/sep`).
- `output` is not set, so the bar appears on every monitor, `HEADLESS-1` (Sunshine) included.
- The clock shows `HH:MM · 15 ноября`: `locale = "ru_RU.UTF-8"` (enabled in `locale.nix`) and the `L` prefix in the format are both needed, otherwise the month is in English.
- A click on a window icon runs `hyprctl dispatch 'hl.dsp.focus({ window = "address:..." })'` (`on-click-window`). The Lua config has no legacy dispatcher names, so `focuswindow` would fail.
- A window icon in the workspace taskbar comes from a desktop entry whose file name equals the window class (`hyprctl clients`, field `class`). An app whose entry has another name shows no icon. Rider's entry in `home-config/shared/rider.nix` is named `jetbrains-rider` for this reason.
- Icons come from JetBrainsMono Nerd Font (`system-config/nixos/hyprland.nix`).

## Palette from the wallpaper

How the palette is built, written and reloaded: `docs/hyprland.md`. `waybar.css` imports `~/.local/state/wallpaper-palette/waybar.css` and uses only the colour names `glass_fill` (island background), `glass_border`, `fg`, `fg_dim`, `accent`, `surface`, `on_primary`, `error`; a new name needs a line in `palette/waybar.css`. `--source-color-index 0` takes the most dominant colour of the image, which follows what the eye sees; `--prefer saturation` takes the most vivid one, an accent that the picture barely shows.

## Modules and indicators

- Right island, in order: layout, network, sound, microphone (`custom/mic`), `custom/failed`, `idle_inhibitor`, tray. Dots separate every module, the tray included.
- `custom/failed`: the number of open `failure-notify` records, hidden when there are none (empty output hides a custom module); the dot before it is a module of its own, `custom/failed-dot`, with the same condition, so no separator is left behind and every gap is built the same way (module padding 5px, `spacing` 5px, dot padding 0). Buttons (`idle_inhibitor`, tray items) get their GTK padding, border and minimum width reset for the same reason; the offsets of `idle_inhibitor` (extra 5px on the right) and `#tray` in `waybar.css` were measured on a screenshot, not derived. A click lists the records in kitty. A failed start of `wg-quick-awg0` or of its `-awg-prepare` unit is recorded through `services.failure-notify` in `sing-box.nix`, so the tunnel has no indicator of its own.
- Indicator glyphs use one Pango size (`icon` helper in `waybar.nix`, `x-large`), so they match each other and the 20px tray icons; plain text is 15px and is raised with `rise` (`text` helper) to share the glyph's vertical centre; if the text looks too high or low, change the `rise` value.
- `custom/mic` (`waybar-mic.sh`) shows a physical microphone only (`alsa_input`/`bluez_input` source) and hides without one. It is event-driven: `pactl subscribe` reports every source change, so a mute from another app or a plugged-in headset updates the bar at once, with no polling. `audio.nix` defines the always-present virtual source `Virtual-Mumble-Microphone`, and PipeWire adds a null source when no device exists, so a source-type `wireplumber` module that follows the default source never hid. A click mutes the microphone.
- `hyprland/language`: a left click runs `hyprctl switchxkblayout all next`, a right click opens Waybar's own GTK menu (`menu`, `menu-file`, `menu-actions`) under the module, so it needs no position of its own; rofi cannot be anchored to a module and its offsets put the list off the screen edge. `all` switches every keyboard, so the virtual keyboard of Sunshine follows. The layouts are one list, `layouts.nix`: `hyprland.nix` fills `@kb_layout@` of `input:kb_layout` from it and `waybar.nix` builds the menu (item index = layout index). `menu`, `menuitem` and `tooltip` (so tray menus and tooltips too) are styled in `waybar.css` with the glass tokens; the popup window around a panel has its decoration (theme shadow, border, corners) reset, otherwise a second outline with its own corners shows, and the layer rule's `blur_popups = true` in `hyprland/rules.lua` blurs the menu behind it (the global `blur.popups` alone did not; it is still set in `settings.lua`, and whether it is needed too was not tested).
- `idle_inhibitor` blocks `hypridle` until the bar restarts.
- `custom/media` (centre island) is `waybar-media.sh`: `playerctl -p playerctld --follow` prints one JSON line per player event, the title is cut at 40 characters, and a click toggles play/pause. `services.playerctld` follows the most recently active player, so a browser tab counts. Waybar's own `mpris` module has no cover art, which is why this is a custom module.
- The cover is one file, `~/.cache/waybar/media-cover`: `image-path` is static, the module reloads the file on every update and the script rewrites it (`file://` copied, `https://` fetched with a 5 s limit, removed when a track has no art; Waybar then logs a failed image load).

## Night colour

`wlsunset.nix` (Minsk coordinates, 6500 K by day, 3500 K at night) derives sunrise and sunset from latitude and longitude; `hyprsunset` has only fixed times. 3500 K is a judgement call between the common defaults (3400 K f.lux evening, 3500 K Redshift, 4000 K wlsunset); change `temperature.night` to taste.

## Blur

The `waybar` layer is one of the glass layers blurred by `hyprland/rules.lua` (`docs/hyprland.md`); `ignore_alpha = 0.1` leaves the transparent gaps between islands unblurred.

## Troubleshooting

- Bar without icons: the font is missing (`fc-list | grep -i jetbrainsmono`).
- Bar keeps old colours after a wallpaper change: `systemctl --user status random-wallpaper waybar`; the script reloads with `try-reload-or-restart`, which sends SIGUSR2.
- Bar has no background: `~/.local/state/wallpaper-palette/waybar.css` is missing or has a syntax error; `journalctl --user -u waybar` shows the CSS error.
