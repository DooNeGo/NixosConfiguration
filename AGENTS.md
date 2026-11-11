# AGENTS.md

## Overview

Personal NixOS + Home Manager configuration for the host `nixos` (x86_64-linux, Hyprland desktop, NVIDIA), plus nix-darwin + Home Manager for the owner's `macbook-air-m1` (aarch64-darwin). There is no test suite; verification means evaluating/building the Nix outputs. The darwin outputs cannot be built on this machine: evaluate them here, the owner builds and switches on the Mac. Agents run as `openclaw-npm`, which has no sudo: build and verify, then hand `switch` (`nixos-rebuild`, `home-manager`) and any `chown`/`rm` under `/home` or `/games` to the owner. When a command fails for lack of permission, ask the owner instead of looking for a workaround.

Ignore `openclaw-local/` and other nix-openclaw workspace files (a separate agent), `reports/` and `research_notes/` (untracked research), the data in `assets/` and `result` in the root.

## Git workflow

Work on a branch, build-verify, and commit only when asked. Merge into `main`, rebase a branch, push and delete a branch only when asked, and rebase only the branch the owner names. The usual sequence is: commit on the branch, then merge, then delete the branch, then rebase the next branch in the queue. `.claude/settings.json` asks before `rebase`, `push`, `branch -D` and `reset --hard`.

## Multiple independent flakes

This repo is **not** one flake. Each flake has its own `flake.lock`, no flake pulls in another, and the repo root has no flake:

| Flake | Output | Applies to |
|---|---|---|
| `system-config/nixos/` | `nixosConfigurations.nixos` | the whole system |
| `system-config/darwin/` | `darwinConfigurations.macbook-air-m1` (nix-darwin, nix-homebrew) | the MacBook system |
| `home-config/DooNeGo/` | `homeConfigurations.DooNeGo` | the MacBook user (standalone Home Manager, like the Linux users) |
| `home-config/mathew/` | `homeConfigurations.mathew` | desktop user `mathew` (Hyprland, waybar, kitty…) |
| `home-config/openclaw-npm/` | `homeConfigurations.openclaw-npm` | agent/dev user (MAUI/Android SDK, Rider, nix-ld) |
| `kokoro/` | Russian TTS packages (`kokoro-ru`, `ruaccent`, `pycrfsuite`, pinned data trees) + `cli/kokoro_cli.py` | standalone; pinned to its own nixpkgs rev |

`lib/pkgs.nix` is a plain function (not a flake) used by the NixOS flake and the home flakes: base nixpkgs `config`, the `pkgs.stable` overlay (`channelsOverlay`), the Rider overlay and `mkPkgs` for Home Manager; each flake passes its own `inputs`, `cudaSupport` stays per host (`extraConfig`). `kokoro/` is standalone and does not use it.

`home-config/shared/*.nix` (git, git-identity, zsh, ssh, rider, maui-dev) are plain modules imported by several user configs; one imported by `DooNeGo` must also evaluate on darwin (guard Linux-only parts with `pkgs.stdenv.hostPlatform.isLinux`). `system-config/nixos/configuration.nix` is the import list for system modules. `system-config/shared/` holds system modules meant for both NixOS and nix-darwin: write them only with options both module systems have (`environment.*`, `programs.tmux.extraConfig`), or the darwin host cannot import them.

## Commands (run from repo root)

Flakes only see git-tracked files: a new file needs `git add -N` before any eval/build, otherwise Nix fails with "not tracked by Git" (the `Write` hook in `.claude/settings.json` does it; files made by other means need it by hand). The `Stop` hook runs `scripts/lint.sh` when `.nix`, `.sh` or `.zsh` files changed.

```sh
nix build --no-link ./system-config/nixos#nixosConfigurations.nixos.config.system.build.toplevel   # build the system without applying
nix eval ./system-config/nixos#nixosConfigurations.nixos.config.<opt>    # inspect an option
home-manager build --flake ./home-config/mathew#mathew
home-manager build --flake ./home-config/openclaw-npm#openclaw-npm
nix build ./kokoro#kokoro-ru
nix eval --raw ./system-config/darwin#darwinConfigurations.macbook-air-m1.config.system.build.toplevel.drvPath   # darwin: evaluation only
nix eval --raw ./home-config/DooNeGo#homeConfigurations.DooNeGo.activationPackage.drvPath
nix flake update --flake ./home-config/openclaw-npm  # per-flake lock update ("Update flake" commits)
scripts/lint.sh                                       # deadnix + statix + nixfmt --check over all flakes (config: statix.toml), shellcheck over tracked *.sh, zsh -n over *.zsh
nixfmt <file>.nix                                     # format the files you changed
```

`deadnix --edit` can break flake `outputs`: a closed pattern like `{ self, nixpkgs }:` must keep `...` after `self` is dropped. Rebuild or evaluate every flake after an auto-fix.

`home-config/openclaw-npm/scripts/config-check.sh` validates an OpenClaw config on an isolated temp state dir without touching `~/.openclaw`.

## Desktop session and remote access

Reasons, pairing and troubleshooting: `docs/remote-access.md`.

- No autologin. The Hyprland (UWSM) session is started on demand over ssh: `sudo systemctl start hyprland-mathew` (`system-config/nixos/hyprland-session.nix`); `stop` ends it. The unit takes tty1 and stops SDDM, which `ExecStopPost` starts again; physical login still goes through SDDM.
- Steam Remote Play without a desktop session: `sudo systemctl start steam-bigpicture-mathew` (`system-config/nixos/steam-bigpicture-session.nix`, headless gamescope, `stop` ends it); do not log in physically as `mathew` meanwhile, one Steam per user.
- The unit exports `HYPRLAND_START_LOCKED`, and `home-config/mathew/hyprland.lua` then starts `hyprlock`, so a remotely started session is locked.
- The session must be the UWSM one (`defaultSession = "hyprland-uwsm"`, same command in the unit): Home Manager session variables (NVIDIA env) reach the compositor only through `~/.config/uwsm/env`.
- Sunshine (`system-config/nixos/remote-access.nix`) runs as `mathew` only, captures with `wlr` the virtual `HEADLESS-1` output that `hyprland.lua` creates; `DP-2` is a physical monitor that is normally off. Audio for streaming goes through the system-wide PipeWire virtual sinks in `audio.nix` (`spatializer`, `Null-Sink`).
- Games run under `mathew` (Steam with `PULSE_SINK` set in `steam.nix`); a separate `games` user is out of scope because headless Steam on NVIDIA and per-account Steam login cost more than the isolation is worth. `openclaw-npm` stays a separate non-wheel user for agents and the Rider backend; keep its name, because renaming moves `/home` state (Nix profiles, `~/.openclaw`) for no isolation gain.
- Rider is pinned in one place, `overlays/rider.nix`, used by `mathew` and `DooNeGo` (Remote Development clients) and `openclaw-npm` (backend); versions must match, so a version bump updates the hash of every system in that file.

## Verifying a change

| Changed path | Build |
|---|---|
| `system-config/nixos/` | the system `toplevel` |
| `system-config/darwin/` | the darwin `drvPath` eval |
| `system-config/shared/` | the system `toplevel` and the darwin eval |
| `home-config/DooNeGo/` | the `DooNeGo` `drvPath` eval |
| `home-config/mathew/` | `home-manager build --flake ./home-config/mathew#mathew` |
| `home-config/openclaw-npm/` | `home-manager build --flake ./home-config/openclaw-npm#openclaw-npm` |
| `home-config/shared/` | both home builds and the `DooNeGo` eval |
| `lib/`, `overlays/` | both home builds, the system build and the `DooNeGo` eval |
| `kokoro/` | `nix build ./kokoro#kokoro-ru` |

When a build fails, rerun it without output redirection and read `2>&1 | tail -30`. Report to the owner the exact `switch` commands and what could not be verified without running (a service start, a session, a mount).

In a review (`/code-review`), report what causes wrong behaviour, a failing check or a misleading result; leave out pure style and naming.

## Conventions and gotchas

- Btrfs (NVMe with subvolumes `@root @home @nix @games @log @nocow`, backup HDD at `/backup`): mounts are in `system-config/nixos/file-systems.nix`, backups in `backup.nix`; decisions, measurements and the runbook are in `docs/btrfs.md`. Settled, not to be reopened: `compress-force=zstd:-1` on the NVMe, `zstd:5` on the HDD; bees stays written but disabled; automount only for the HDD.
  - A filesystem UUID is written once, in its `fileSystems.<mount>.device`; derive it from there everywhere else.
  - tmpfiles rules are skipped below an automount (`/backup`): declare such directories in `mountDirs`, which applies them when the disk is mounted and so cannot create them on the filesystem underneath.
  - Only the owner runs `btrfs`/`btrbk` as root.
- Report failures through `system-config/nixos/failure-notify.nix`: add the service to `services.failure-notify.units`, or call `failure-notify report` from a handler. It already delivers to shells and desktop sessions without root touching a session bus, so a unit needs no `OnFailure` or `notify-send` of its own.
- Keep logic out of `.nix` files: a shell script over ~20 lines, or with functions, option parsing, `flock` or `trap`, goes into a `.sh` (zsh: `.zsh`) next to its module, read with `builtins.readFile`; values from Nix reach it through `runtimeEnv`. A short, plain script may stay inline. Writing such a file: `.claude/rules/shell-tools.md`.
- Before hand-writing a systemd unit, check whether the pinned nixpkgs already has an upstream module/option for it.
- Layering: `environment.systemPackages` / `systemd.tmpfiles.rules` are system-level only (not valid in Home Manager). tmpfiles rules must create the full directory chain.
- Secrets use agenix: `secrets.nix` lists recipients (host key only), encrypted files in `secrets/*.age`. Never print or commit plaintext secrets. Create one with `agenix -e secrets/<name>.age` from the repo root after adding it to `secrets.nix`. The murmur password is such a secret (`environmentFile`). The `sing-box` config is generated by `system-config/nixos/sing-box/generate-config.py` from agenix credentials (`resolve-credential.sh`).
- `git status` may show lock-file changes you didn't make (e.g. `flake.lock`); report them separately rather than folding them into your change.
- The repo is shared by group `users` (`mathew` and `openclaw-npm`): `.git` must stay group-writable, otherwise commits and branch switches fail with permission errors (fix: `chmod -R g+w .git`). `system-config/nixos/shared-repo-acl.nix` gives the group a recursive default ACL on the repo, so new files stay writable for both users; it takes effect after the owner's `switch`.
