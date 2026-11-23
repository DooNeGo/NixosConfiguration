# Remote access: Hyprland, Sunshine, Steam Remote Play

How the remote sessions work and why they are built this way. The units and settings themselves are in the modules named below; this file holds what the code does not show.

## Session model

- No autologin: with autologin Xwayland does not start in the `mathew` session (Steam and other X11 apps fail, and Sunshine needs a `DISPLAY` workaround). The session is chosen with `defaultSession = "hyprland-uwsm"` instead.
- The owner starts the stream session over ssh: `systemctl start hyprland-headless-mathew` (`hyprland-session.nix`). The unit runs the same UWSM command as SDDM, because Home Manager session variables (NVIDIA env) reach the compositor only through `~/.config/uwsm/env`. A physical login goes through SDDM.
- The remote session starts locked (`HYPRLAND_START_LOCKED` → `hyprlock-initial.service`). Start order (`home-config/mathew/hyprlock-initial.nix`, `remote-access.nix`): `hyprpaper`, `random-wallpaper`, `waybar` → `hyprlock-initial.service` (its `ExecStartPre` waits until waybar is active and both layers are on the output, 30 s at most, then locks anyway) → `sunshine.service`. Sunshine requires the lock unit: hyprlock signals readiness only after the compositor confirms the session lock, and a failed lock prevents capture. A successful retry starts Sunshine. In a local login the lock unit's condition skips it.
- The lock must start after the desktop has drawn. A lock started earlier fades out into the compositor's flat background colour (`#121212`) before the desktop appears: the stream shows a near-black frame for 0.7 s at the first unlock. With the lock started later, its fade-out (`hyprlock.nix`, 0.3 s) shows the desktop. `misc.session_lock_xray` makes no difference (tested on and off; the idle cost is the same).
- `hyprlock-initial` waits for the compositor’s lock confirmation, times out if it does not arrive, and restarts after a crash (not after an unlock). The initial lock uses a small hyprlock build override to send systemd readiness on that confirmation. A new hyprlock can take over a dead lock only with `misc.allow_session_lock_restore` (`hyprland/settings.lua`): without it Hyprland keeps its red lock-dead screen and every new hyprlock crashes with SEGV; a restart on `home-manager switch` would kill hyprlock under the lock, so the unit has `X-SwitchMethod = "keep-old"`. A failure is visible in `systemctl --user status` only: `failure-notify` covers system services.
- A unit pulled in by `graphical-session.target` needs `After=graphical-session.target` itself: a target gets an implicit `After=` on every unit it wants, and without it `random-wallpaper` (which is `After=` the target) closes an ordering cycle. Such a unit is also `PartOf=` the target, otherwise it stays active between sessions of the same user manager.

## Sunshine (`remote-access.nix`)

- Runs as `mathew` only. `capture = "wlr"` captures the virtual `HEADLESS-1` output created in `hyprland/session.lua` (only in a remote start, so a local login at SDDM has no extra monitor) (1680x1050@60, the aspect ratio of the owner's client, a 16:10 laptop; a mismatch letterboxes the picture). `DP-2` is a physical monitor that is normally off.
- Capture is `wlr`, not KMS (KMS needs the remote access re-confirmed in front of the machine) and not NvFBC (X11 only); NVENC only encodes.
- `lan_encryption_mode = 0`, `wan_encryption_mode = 1`: encryption off on the LAN, on over WAN. Tailscale traffic is already encrypted.
- `csrf_allowed_origins` lists the host names the web UI is opened under (`https://nixos`, the Tailscale address); without them the web UI rejects the requests.

## Pairing

- The web UI is `https://<host>:47990` (https, self-signed certificate); `http` shows nothing.
- Moonlight "client is not authorized / certificate verification failed": leftover clients of failed pairing attempts. Fix: remove all clients in the web UI (Troubleshooting → Unpair all), remove the host in Moonlight, add it again, and enter the PIN while the Moonlight dialog is still open.

## Steam Remote Play without a desktop (`steam-bigpicture-session.nix`)

- `systemctl start steam-bigpicture-mathew` runs Steam Big Picture in gamescope with the headless backend: no monitor, no tty, no Hyprland, no nesting. Remote Play captures gamescope's PipeWire stream and encodes with NVENC. The unit conflicts with `hyprland-headless-mathew`: one Steam per user.
- The stream size is fixed when gamescope starts (`width`/`height` in the module); a client cannot change it, so a new client aspect ratio means editing the Nix file.
- The Home Manager cursor theme (`rose-pine-hyprcursor`) has no X11 cursors, so gamescope draws a huge fallback cursor. The unit exports an XCursor theme (Adwaita, size 12) after `hm-session-vars`.

## Session without tty1 (`hyprland-headless-mathew`)

- Hyprland has no headless-only mode: aquamarine's backend list is fixed (headless, DRM, wayland) and `AQ_BACKENDS` is not read by Hyprland 0.57.1 or aquamarine 0.16.0. Without a seat the DRM backend fails with `CBackend::create() failed!`, and upstream requires DRM access (hyprwm/Hyprland discussions #10263, #12689).
- The workaround: `LIBSEAT_BACKEND=noop` lets the DRM backend open the DRM devices directly, `AQ_NO_KMS_REQUIREMENT` keeps it from requiring a usable output. `AQ_DRM_DEVICES` stays unset on purpose: the `cardN` numbers change between boots (the GPU was `card0`, then `card1` once `simple-framebuffer` took `card0`), and aquamarine splits the variable on `:` with no escaping, so a stable `/dev/dri/by-path/pci-0000:01:00.0-card` cannot be written in it. SDDM keeps tty1 and its DRM master, so nothing is shown on DP-2; only `HEADLESS-1` exists.
- Without the `hyprctl output create headless HEADLESS-1` of `hyprland/session.lua` Hyprland has no monitor at all (`hyprctl monitors all` is `[]`; measured in the box): `AQ_NO_KMS_REQUIREMENT` only lets it start, it does not create an output.
- `mathew` needs the `video` group for the DRM card (logind's ACL goes only to the active seat0 session). A user manager started before the group was added does not have it: `systemctl restart user@1000.service` after the first `switch`, otherwise `wayland-wm@` dies with `CBackend::create() failed!`.
- `uwsm` looks the session up by the foreground VT and fails without a seat, so `XDG_SEAT=seat0` is passed to `uwsm start` only through `env`. In the unit `Environment` it reaches `pam_systemd`, which then does not create `XDG_RUNTIME_DIR`.
- Sunshine's virtual keyboard and mouse need `/dev/uinput`: logind's ACL goes to the active seat0 session, which here is the SDDM greeter, so `mathew` is in the `uinput` group. Like `video`, a new group reaches Sunshine only after `systemctl restart user@1000.service`.
- The Sunshine user unit starts for `mathew` only: the SDDM greeter session reaches `graphical-session.target` too, and a Sunshine run as `sddm` held the ports.
- Hyprland reads every `/dev/input/*` device under `noop`, and the greeter shares seat0, so Moonlight input can also reach the greeter and the physical keyboard can reach the locked stream session.
- Conflicts with `steam-bigpicture-mathew` (one Hyprland, one Steam per user).
- A seat session and the stream session of `mathew` exclude each other, because one user manager serves both (`graphical-session.target`, Sunshine, Steam). The unit refuses to start while `mathew` has a session on a seat (`ExecStartPre`), and the `sddm` PAM stack refuses `mathew` while the unit runs; nothing is stopped automatically. The unit also `requires` `display-manager.service`: SDDM keeps DRM master on DP-2, so a stopped SDDM stops the stream session too.
- uwsm exports the unit environment (`LIBSEAT_BACKEND`, `AQ_*`) into the user manager, since Hyprland starts from it; the variables stay there until the session stops and uwsm cleans them up.
