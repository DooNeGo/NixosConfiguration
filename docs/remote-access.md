# Remote access: Hyprland, Sunshine, Steam Remote Play

What was decided and why. The units and settings themselves are in the modules named below; this file holds what the code does not show.

## Session model

- No autologin. With autologin Xwayland did not start in the `mathew` session (Steam and other X11 apps failed, and Sunshine needed a `DISPLAY` workaround); after the autologin was dropped and `defaultSession = "hyprland-uwsm"` set, both problems disappeared and the workaround was removed.
- The owner starts the session over ssh: `systemctl start hyprland-mathew` (`hyprland-session.nix`). The unit runs the same UWSM command as SDDM, because Home Manager session variables (NVIDIA env) reach the compositor only through `~/.config/uwsm/env`.
- The session starts locked (`HYPRLAND_START_LOCKED` → `hyprlock` in `hyprland.lua`), so nobody at the physical keyboard sees a remotely opened desktop.
- Standalone Home Manager for `mathew` (not a NixOS module) was suspected of causing the Xwayland failure and ruled out.

## Sunshine (`remote-access.nix`)

- Runs as `mathew` only. `capture = "wlr"` captures the virtual `HEADLESS-1` output created in `hyprland.lua` (1680x1050@60, the aspect ratio of the owner's client, a 16:10 laptop; a mismatch letterboxes the picture). `DP-2` is a physical monitor that is normally off.
- KMS capture was tried and did not fix the problem it was tried for; it also needs the remote access re-confirmed in front of the machine. NvFBC is X11-only and is not used; NVENC only encodes.
- `lan_encryption_mode = 0`, `wan_encryption_mode = 1`: encryption off on the LAN, on over WAN. Tailscale traffic is already encrypted.
- `csrf_allowed_origins` lists the host names the web UI is opened under (`https://nixos`, the Tailscale address); without them the web UI rejects the requests.

## Pairing

- The web UI is `https://<host>:47990` (https, self-signed certificate); `http` shows nothing.
- Moonlight "client is not authorized / certificate verification failed" came from leftover clients of failed pairing attempts. Fix: remove all clients in the web UI (Troubleshooting → Unpair all), remove the host in Moonlight, add it again, and enter the PIN while the Moonlight dialog is still open.

## Steam Remote Play without a desktop (`steam-bigpicture-session.nix`)

- `systemctl start steam-bigpicture-mathew` runs Steam Big Picture in gamescope with the headless backend: no monitor, no tty, no Hyprland, no nesting. Remote Play captures gamescope's PipeWire stream and encodes with NVENC. The unit conflicts with `hyprland-mathew`: one Steam per user.
- The stream size is fixed when gamescope starts (`width`/`height` in the module); a client cannot change it, so a new client aspect ratio means editing the Nix file.
- The Home Manager cursor theme (`rose-pine-hyprcursor`) has no X11 cursors, so gamescope drew a huge fallback cursor. The unit exports an XCursor theme (Adwaita, size 12) after `hm-session-vars`.
- A separate `games` user for Steam was tried on a branch and dropped: headless Steam on NVIDIA and per-account Steam login cost more than the isolation gave.

## Session without tty1 (`hyprland-headless-mathew`)

- Hyprland has no headless-only mode: aquamarine's backend list is fixed (headless, DRM, wayland) and `AQ_BACKENDS` is not read by Hyprland 0.57.1 or aquamarine 0.16.0. Without a seat the DRM backend fails and the throw is `CBackend::create() failed!`. Upstream says Hyprland needs DRM access (hyprwm/Hyprland discussions #10263, #12689); no public recipe for a seatless Hyprland was found.
- What works: `LIBSEAT_BACKEND=noop` lets the DRM backend open `/dev/dri/card0` directly, `AQ_DRM_DEVICES` and `AQ_NO_KMS_REQUIREMENT` keep it from requiring a usable output. SDDM keeps tty1 and its DRM master, so nothing is shown on DP-2; only `HEADLESS-1` exists.
- `mathew` needs the `video` group for `card0` (logind's ACL goes only to the active seat0 session). A user manager started before the group was added does not have it: `systemctl restart user@1000.service` after the first `switch`, otherwise `wayland-wm@` dies with `CBackend::create() failed!`.
- `uwsm` looks the session up by the foreground VT and fails without a seat, so `XDG_SEAT=seat0` is passed to `uwsm start` only through `env`. In the unit `Environment` it reaches `pam_systemd`, which then does not create `XDG_RUNTIME_DIR`.
- Sunshine's virtual keyboard and mouse need `/dev/uinput`: logind's ACL goes to the active seat0 session, which here is the SDDM greeter, so `mathew` is in the `uinput` group. Like `video`, a new group reaches Sunshine only after `systemctl restart user@1000.service`.
- The Sunshine user unit starts for `mathew` only: the SDDM greeter session reaches `graphical-session.target` too, and a Sunshine run as `sddm` held the ports.
- Hyprland reads every `/dev/input/*` device under `noop`, and the greeter shares seat0, so Moonlight input can also reach the greeter and the physical keyboard can reach the locked stream session.
- Conflicts with `hyprland-mathew` and `steam-bigpicture-mathew` (one Hyprland, one Steam per user).
- A seat session and the stream session of `mathew` exclude each other, because one user manager serves both (`graphical-session.target`, Sunshine, Steam). The unit refuses to start while `mathew` has a session on a seat (`ExecStartPre`), and the `sddm` PAM stack refuses `mathew` while the unit runs; nothing is stopped automatically. The unit also `requires` `display-manager.service`: SDDM keeps DRM master on DP-2, so a stopped SDDM (for example under `hyprland-mathew`) stops the stream session too.
- uwsm exports the unit environment (`LIBSEAT_BACKEND`, `AQ_*`) into the user manager, since Hyprland starts from it; the variables stay there until the session stops and uwsm cleans them up.
