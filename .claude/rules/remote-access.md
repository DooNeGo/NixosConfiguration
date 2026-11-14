---
paths:
  - "system-config/nixos/hyprland-session.nix"
  - "system-config/nixos/steam-bigpicture-session.nix"
  - "system-config/nixos/remote-access.nix"
  - "system-config/nixos/sddm.nix"
  - "system-config/nixos/audio.nix"
  - "home-config/mathew/hyprland.lua"
  - "docs/remote-access.md"
---

# Desktop session and remote access

Reasons, pairing and troubleshooting: `docs/remote-access.md`.

- No autologin. The Hyprland (UWSM) session is started on demand over ssh: `sudo systemctl start hyprland-mathew` (`system-config/nixos/hyprland-session.nix`); `stop` ends it. The unit takes tty1 and stops SDDM, which `ExecStopPost` starts again; physical login still goes through SDDM.
- A session for Sunshine that leaves tty1 and SDDM alone: `sudo systemctl start hyprland-headless-mathew` (same module; only `HEADLESS-1` exists). It conflicts with `hyprland-mathew` and `steam-bigpicture-mathew`.
- Steam Remote Play without a desktop session: `sudo systemctl start steam-bigpicture-mathew` (`system-config/nixos/steam-bigpicture-session.nix`, headless gamescope, `stop` ends it); do not log in physically as `mathew` meanwhile, one Steam per user.
- The unit exports `HYPRLAND_START_LOCKED`, and `home-config/mathew/hyprland.lua` then starts `hyprlock`, so a remotely started session is locked.
- The session must be the UWSM one (`defaultSession = "hyprland-uwsm"`, same command in the unit): Home Manager session variables (NVIDIA env) reach the compositor only through `~/.config/uwsm/env`.
- Sunshine (`system-config/nixos/remote-access.nix`) runs as `mathew` only, captures with `wlr` the virtual `HEADLESS-1` output that `hyprland.lua` creates; `DP-2` is a physical monitor that is normally off. Audio for streaming goes through the system-wide PipeWire virtual sinks in `audio.nix` (`spatializer`, `Null-Sink`).
