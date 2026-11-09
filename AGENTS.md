# AGENTS.md

## Overview

Personal NixOS + Home Manager configuration for a single host (`nixos`, x86_64-linux, Hyprland desktop, NVIDIA). There is no test suite; verification means evaluating/building the Nix outputs. Agents run as `openclaw-npm`, which has no sudo: build and verify, then hand `switch` (`nixos-rebuild`, `home-manager`) and any `chown`/`rm` under `/home` or `/games` to the owner.

## Multiple independent flakes

This repo is **not** one flake. Each flake has its own `flake.lock`, and the root flake does NOT pull in the others:

| Flake | Output | Applies to |
|---|---|---|
| `./flake.nix` | `nixosConfigurations.nixos` (modules in `system-config/`) | the whole system |
| `home-config/mathew/` | `homeConfigurations.mathew` | desktop user `mathew` (Hyprland, waybar, kitty…) |
| `home-config/openclaw-npm/` | `homeConfigurations.openclaw-npm` | agent/dev user (MAUI/Android SDK, Rider, nix-ld) |
| `kokoro/` | Russian TTS packages (`kokoro-ru`, `ruaccent`, `pycrfsuite`, pinned data trees) + `cli/kokoro_cli.py` | standalone; pinned to its own nixpkgs rev |

`lib/pkgs.nix` is a plain function (not a flake) used by the root flake and both home flakes: base nixpkgs `config`, the `pkgs.stable`/`pkgs.unstable` overlay (`channelsOverlay`) and `mkPkgs` for Home Manager; each flake passes its own `inputs`, `cudaSupport` stays per host (`extraConfig`). `kokoro/` is standalone and does not use it.

`home-config/shared/*.nix` (git, zsh, ssh, maui-dev) are plain modules imported by several user configs. `system-config/configuration.nix` is the import list for system modules; commented-out imports are intentionally disabled.

## Commands (run from repo root)

Flakes only see git-tracked files: `git add -N <new file>` before any eval/build, otherwise Nix fails with "not tracked by Git".

```sh
nix build --no-link .#nixosConfigurations.nixos.config.system.build.toplevel   # build the system without applying
nix eval .#nixosConfigurations.nixos.config.<opt>    # inspect an option
home-manager build --flake ./home-config/mathew#mathew
home-manager build --flake ./home-config/openclaw-npm#openclaw-npm
nix build ./kokoro#kokoro-ru
nix flake update --flake ./home-config/openclaw-npm  # per-flake lock update ("Update flake" commits)
scripts/lint.sh                                       # deadnix + statix (system packages) over all flakes (config: statix.toml)
```

`deadnix --edit` can break flake `outputs`: a closed pattern like `{ self, nixpkgs }:` must keep `...` after `self` is dropped. Rebuild all four flakes after an auto-fix.

`home-config/openclaw-npm/scripts/config-check.sh` validates an OpenClaw config on an isolated temp state dir without touching `~/.openclaw`.

## Desktop session and remote access

- No autologin. The Hyprland (UWSM) session is started on demand over ssh: `sudo systemctl start hyprland-mathew` (`system-config/hyprland-session.nix`); `stop` ends it. The unit takes tty1 and stops SDDM, which `ExecStopPost` starts again; physical login still goes through SDDM.
- The unit exports `HYPRLAND_START_LOCKED`, and `home-config/mathew/hyprland.lua` then starts `hyprlock`, so a remotely started session is locked.
- The session must be the UWSM one (`defaultSession = "hyprland-uwsm"`, same command in the unit): Home Manager session variables (NVIDIA env) reach the compositor only through `~/.config/uwsm/env`.
- Sunshine (`system-config/remote-access.nix`) runs as `mathew` only, captures with `wlr` the virtual `HEADLESS-1` output that `hyprland.lua` creates; `DP-2` is a physical monitor that is normally off. Audio for streaming goes through the system-wide PipeWire virtual sinks in `audio.nix` (`spatializer`, `Null-Sink`).
- Games run under `mathew` (Steam with `PULSE_SINK` set in `steam.nix`); a separate `games` user is out of scope because headless Steam on NVIDIA and per-account Steam login cost more than the isolation is worth. `openclaw-npm` stays a separate non-wheel user for agents and the Rider backend; keep its name, because renaming moves `/home` state (Nix profiles, `~/.openclaw`) for no isolation gain.
- Rider is pinned in one place, `home-config/shared/overlays/rider.nix`, used by both `mathew` (Remote Development client) and `openclaw-npm` (backend); versions must match.

## Conventions and gotchas

- Btrfs (single NVMe filesystem, subvolumes `@root @home @nix @games @log @nocow`): tuning, bees dedup, recompress and btrbk backups are described in `docs/btrfs.md`. All mounts and their options live in `system-config/file-systems.nix` (`hardware-configuration.nix` only supplies device and subvolume); filesystem UUIDs are derived from `fileSystems.<mount>.device`, never repeated. The top-level subvolume is mounted at `/mnt/btrfs-top`. `/games`, `/var/lib/nocow` and `/backup` are automounts the system boots without, so tmpfiles rules do not apply to them. `@home` (btrbk instance `home`) and `@root` (instance `system`) are backed up to the HDD mounted at `/backup`; `/backup` is root-only (`chmod 700`) and `/backup/btrbk` is created by hand on purpose (see the runbook). Only the owner runs `btrfs`/`btrbk` as root.
- Failure reporting: `system-config/failure-notify.nix`. A module registers its services in `services.failure-notify.units`; anything else reports with `failure-notify report [--ttl s] <id> <message>`. Records live in `/var/lib/failure-notify/`, are shown by every zsh (start and before the prompt) and handed to the `sinks` executables (currently `systembus-notify`, shown by mako).
- Before hand-writing a systemd unit, check whether the pinned nixpkgs already has an upstream module/option for it.
- Layering: `environment.systemPackages` / `systemd.tmpfiles.rules` are system-level only (not valid in Home Manager). tmpfiles rules must create the full directory chain.
- Secrets use agenix: `secrets.nix` lists recipients (host key only), encrypted files in `secrets/*.age`. Never print or commit plaintext secrets. Create one with `agenix -e secrets/<name>.age` from the repo root after adding it to `secrets.nix`. The murmur password is such a secret (`environmentFile`). The `sing-box` config is generated by `system-config/sing-box/generate-config.py` from agenix credentials (`resolve-credential.sh`).
- `git status` may show lock-file changes you didn't make (e.g. `flake.lock`); report them separately rather than folding them into your change.
- The repo is shared by group `users` (`mathew` and `openclaw-npm`): `.git` must stay group-writable, otherwise commits and branch switches fail with permission errors (fix: `chmod -R g+w .git`).
