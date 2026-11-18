---
paths:
  - "system-config/nixos/hyprland-session.nix"
  - "system-config/nixos/steam-bigpicture-session.nix"
  - "system-config/nixos/remote-access.nix"
  - "system-config/nixos/sddm.nix"
  - "system-config/nixos/audio.nix"
  - "home-config/mathew/hyprland/session.lua"
  - "home-config/mathew/hyprland/monitors.lua"
  - "home-config/mathew/hyprlock-initial.nix"
  - "docs/remote-access.md"
---

# Desktop session and remote access

Reasons, pairing and troubleshooting: `docs/remote-access.md`.

- No autologin; physical login goes through SDDM. The session for Sunshine is started on demand over ssh: `sudo systemctl start hyprland-headless-mathew` (`system-config/nixos/hyprland-session.nix`; leaves tty1 and SDDM alone, only `HEADLESS-1` exists); `stop` ends it. It conflicts with `steam-bigpicture-mathew`.
- Steam Remote Play without a desktop session: `sudo systemctl start steam-bigpicture-mathew` (`system-config/nixos/steam-bigpicture-session.nix`, headless gamescope, `stop` ends it); do not log in physically as `mathew` meanwhile, one Steam per user.
- The unit exports `HYPRLAND_START_LOCKED`, and `hyprlock-initial.service` (`home-config/mathew/hyprlock-initial.nix`) locks the session once the desktop has drawn, and Sunshine starts after it; a login at SDDM neither sets the variable nor gets the lock.
- Test a change of the session, lock or start order under `testuser` first (`sudo` is not needed: polkit lets `openclaw-npm` start its unit): method and modules in `docs/testuser.md`. The owner's stream is the last check.
- The session must be the UWSM one (`defaultSession = "hyprland-uwsm"`, same command in the unit): Home Manager session variables (NVIDIA env) reach the compositor only through `~/.config/uwsm/env`.
- Sunshine (`system-config/nixos/remote-access.nix`) runs as `mathew` only, captures with `wlr` the virtual `HEADLESS-1` output that `hyprland/session.lua` creates; `DP-2` is a physical monitor that is normally off. Audio for streaming goes through the system-wide PipeWire virtual sinks in `audio.nix` (`spatializer`, `Null-Sink`).
