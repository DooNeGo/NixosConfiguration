# Hyprland configuration

Files: `home-config/mathew/hyprland.nix` (loads the Lua files), `home-config/mathew/hyprland/*.lua`, `wallpaper/` and `palette/` (colours). Session start and the remote sessions: `docs/remote-access.md`. The bar: `docs/waybar.md`.

## Layout of the config

Home Manager writes `~/.config/hypr/hyprland.lua` with one `require("hyprland.<name>")` per entry of `extraLuaFiles`, in name order, and puts the files under `~/.config/hypr/hyprland/`.

| File | Holds |
|---|---|
| `session.lua` | the `hyprland.start` hook: when `HYPRLAND_START_LOCKED` is set (a remote start, not a login at SDDM) creates `HEADLESS-1`; the lock is `hyprlock-initial.service` (`hyprlock-initial.nix`) |
| `monitors.lua` | `DP-2` (2560x1440@180, 10 bit, VRR) and the virtual `HEADLESS-1` for Sunshine, to the right of `DP-2` so the two outputs do not overlap |
| `settings.lua` | gaps, rounding, blur, shadow, input, `misc` |
| `animations.lua` | curves and animations |
| `rules.lua` | window and layer rules |
| `binds.lua` | key and mouse binds |

A file is added in `hyprland.nix` and, if it is new, with `git add -N`.

## Login screen

SDDM runs its greeter under the same Hyprland (`sddm.nix`, `start-hyprland -- -c /etc/sddm/hyprland.lua`) with its own config `system-config/nixos/sddm-hyprland.lua`. Without a config the greeter's Hyprland drew its "config missing" banner and the default wallpaper, and showed them for about a second after the login. The monitor mode and the layouts are copied from `monitors.lua` and `layouts.nix` (another flake), so change them together. The theme is still catppuccin; the look of `style/` is not applied to it.

## Look

- Gaps 5/10, rounding 15 (the bar islands use 20), blur 4x3, inactive windows at 0.85 opacity. The window shadow is light and very soft, without offset: range 40, render power 2, black at alpha 0.2 when focused and 0.1 when not. It tells the window edge better than a border did, and an offset shadow drew a lobe under the window; the values are tuned by eye.
- Windows have no border: the active one is told by the inactive ones' opacity.
- **Style** (`style/default.nix`): the one place for the font, the glass surface (fill alpha 0.3, a 1 px border at alpha 0.16, a blur behind), the corner radii (panel 20 px for bar islands, notifications, launcher panels, lock field and tooltip; inner 12 px for a workspace button and the selected launcher row; window 15 px), the gaps (10 px, inner 5 px) and the palette roles that colour each part (`roles`). Its `tokens` are `@name@` placeholders (`@radius@`, `@gap@`, `@font_family@`, `@role_glass_fill@`...) in the waybar CSS, the rofi theme, the Lua files and the matugen templates; `subst` fills them in at build time, and `mako.nix`, `hyprlock.nix` and `kitty.nix` read the same values as Nix attributes. A new look value is one attribute and one token. The blur is a layer rule per namespace in `rules.lua` (`glassLayers`). The rofi layer namespace is `rofi`.
- Animations: `speed` is in deciseconds. Windows use a critically damped spring (response 0.4 s, Apple's "smooth" idea: no overshoot), workspaces an ease-out curve with a sharp start and a long soft stop; closing windows, fades and layers are short ease-outs.

## Wallpaper palette

`wallpaper/palettes.nix` runs `matugen` over every image at the top level of `assets/wallpapers` (a subdirectory is ignored) at build time and renders each template in `home-config/mathew/palette/` into `wallpaper-palettes/<image>/`. `set-random-wallpaper.sh` copies the chosen set to `~/.local/state/wallpaper-palette/` (rename per file, so no consumer reads a half-written file) and reloads the consumers:

| Template | Consumer | Reload |
|---|---|---|
| `waybar.css` | `waybar.css` imports it | `systemctl --user try-reload-or-restart waybar` |
| `mako` | `include=` in the mako config | `makoctl reload` |
| `kitty.conf` | `include` in `kitty.conf` | `SIGUSR1` to every kitty |
| `rofi.rasi` | `@import` in `rofi-glass.rasi` | none: read at each start |
| `hyprlock.conf` | `source=` in `hyprlock.conf`, defines `$text`, `$accent`, `$glass_fill`, `$glass_border`... (the password field is glass) | read at each lock |

`hyprpaper.service` turns active only once its IPC socket exists (`ExecStartPre` removes a stale socket, `ExecStartPost` waits for the new one, both in `hyprpaper.nix`; the name `.hyprpaper.sock` is hardcoded in hyprpaper, so the wait fails with a message after 10 s if an update renames it), and `random-wallpaper` runs before `waybar.service`, so the script's reload does not hit a waybar that is still starting (SIGUSR2 kills it); that reload is `--no-block`, because waiting for a unit that is ordered after the script itself deadlocks the start (and a `switch`). `~/.local/state/wallpaper-palette/wallpaper` names the current wallpaper, and `lock-background` in the same directory links to its image: hyprlock shows it as its blurred background, because a screenshot is empty when the lock starts before the first wallpaper (remote start). Every `switch` refreshes the directory from that wallpaper's palette (the first wallpaper by name before the script ever ran) and reloads waybar, mako and kitty, so a new template or colour role reaches the consumers without a relogin. A switch from a context without a user session bus (a plain tty or `su`) skips the reload and says so; the consumers then read the palette when they next start. A build fails when matugen leaves a template file out for any wallpaper. The cache of clipboard thumbnails is separate (`clipboard-pick.sh`). A new colour role is one line in the template; a new consumer is one template, one entry in `templates` and a reload line.

## Terminal and shell colours

`palette/kitty.conf` also sets the 16 ANSI colours: black is `surface_container_highest`, bright black `outline`, blue/magenta/cyan are `primary`/`tertiary`/`secondary`, white and bright white are `on_surface_variant` and `on_surface`. Red, green and yellow are matugen custom colours (`[config.custom_colors]` in `wallpaper/palettes.nix`), blended towards the wallpaper's hue, so they stay recognisably red, green and yellow. Everything that uses ANSI colours follows the wallpaper: `zsh-syntax-highlighting`, the autosuggestion (`fg=8`), `ls`, `git`, TUIs.

The prompt (`zsh-theme.nix`, starship, `mathew` only: `shared/zsh.nix` is also imported by hosts without a palette) is one pill (user name, host name in an ssh session only, directory, git, nix shell, command duration) split by a thin Powerline arrow followed by `❯` and the command on the same line. The fill is ANSI blue (the wallpaper primary), the text ANSI black, and the caps are half-circle Powerline glyphs in the fill colour. The fill is opaque on purpose: kitty can make a cell background translucent (`transparent_background_colors`) but a glyph is always opaque, so a translucent pill shows a body of a different shade than its caps. The pills need a Nerd Font in the terminal, also on a client that connects over ssh, whose own ANSI palette colours them (the wallpaper palette exists only in kitty on this host). To render the prompt without the ssh host pill from a script run in an ssh session, unset the variables: `env -u SSH_CONNECTION -u SSH_CLIENT -u SSH_TTY starship prompt`.

## Binds

| Keys | Action |
|---|---|
| `SUPER+arrows` / `+CTRL` / `+ALT` | focus / resize by 40 px / swap |
| `SUPER+wheel` | next or previous workspace |
| `Print`, `SHIFT+Print`, `CTRL+Print` | `hyprshot` region, window, output (file in `~/Pictures/Screenshots` and clipboard) |
| `SUPER+SHIFT+C` | `hyprpicker -a` |
| `SUPER+V` | clipboard history (`clipboard-pick`): `cliphist` list in `rofi -dmenu`, the choice goes to the clipboard and is pasted with `wtype` (`CTRL+SHIFT+V` in a terminal, `CTRL+V` elsewhere; the terminal classes are listed in `clipboard-pick.sh`) |
| `SUPER+L` | `hyprlock` (not started again while one runs) |

rofi is the launcher (`SUPER+E`, drun mode, pressing it again closes it) and the clipboard picker (`SUPER+V`), both in `rofi.nix` with the theme `rofi-glass.rasi`: the input field and the list are two separate glass panels, which fuzzel (one surface) cannot draw. The picker lists an image as a thumbnail right of its text (the theme passed with `-theme-str` in `clipboard-pick.sh`, so text entries have no gap on the left; the launcher keeps icons on the left). A larger icon for the selected row does not work: rofi takes the icon size from the widget, not from the row state (`clipboard-pick.sh` renders each image entry once into `~/.cache/clipboard-pick`, deleted after 7 days). hyprlauncher was replaced: it has no border or panel settings and its `--dmenu` mode (0.1.7) reads a list but never prints the choice, so it cannot feed `cliphist decode`. `services.cliphist` stores text and images from `wl-paste`.

## Rules

- Blur for every glass layer (`waybar`, `notifications`, `rofi`); `ignore_alpha = 0.1` leaves fully transparent areas, such as the gaps between the bar islands, unblurred. `blur_popups = true` in the same rule blurs the popups of the layer (the Waybar menus and tooltips).
- `suppress_event = "maximize"` for every window: kitty and other apps request to start maximized, and a maximized window fills the work area over the others instead of joining the layout (`hyprctl clients` shows `fullscreen: 1`).
- `immediate = true` for `steam_app_.*`: tearing, which lowers latency, applies only to a fullscreen window and needs `allow_tearing` in `settings.lua`.
- The bar layer rule (blur): `docs/waybar.md`.

## Troubleshooting

- Notifications or `kitty` have the default colours: the file in the same directory is missing; run `~/.local/bin/set-random-wallpaper.sh`.
- `SUPER+V` shows nothing: `systemctl --user status cliphist`. The entry is copied but not pasted: the focused window's class is not in the terminal list of `clipboard-pick.sh` (`hyprctl activewindow -j`), or the app ignores virtual-keyboard input.
