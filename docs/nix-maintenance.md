# Nix maintenance: garbage collection, generations, journal

Decisions of the `tune-system` branch and the reasons behind them.

## Garbage collection and generations

- `nix.gc` is replaced by `programs.nh.clean` (`system-config/shared/nh.nix`, imported by NixOS and nix-darwin). It runs weekly (`nh clean all --keep-since 14d --keep N`): besides the store it removes stale system profile generations and result links.
- `generationsKeep` (default 20) is one number for two places: `nh clean --keep` and `boot.loader.systemd-boot.configurationLimit`. A boot entry whose generation was collected would fail to boot, so the menu never lists more generations than `nh clean` keeps. `--keep-since 14d` is the age limit on top of it.
- Home Manager generations are expired per user by `services.home-manager.autoExpire` (`home-config/shared/auto-expire.nix`, 7 days, systemd user timer on Linux, launchd agent on the Mac). `nh clean` is not relied on for them.
- Unverified without the owner: how `nh clean` behaves on the Mac (its launchd job runs as root and may also clean the profiles of `DooNeGo`).

## nix-daemon environment

- `TMPDIR=/var/tmp`: `/tmp` is a tmpfs of half the RAM (`boot.nix`), too small for CUDA and other large builds. `/var/tmp` lives on `@root`, which is snapshotted and backed up; scratch data of a build running at snapshot time is kept until the snapshot expires. Accepted by the owner.
- `HTTP_PROXY` / `HTTPS_PROXY` are read from `config.environment.variables`, set in `sing-box.nix`. `NO_PROXY` is not passed on purpose.

## Journal

`journald.nix`: `SystemMaxUse=500M`, `MaxRetentionSec=1month`. Before, the journal grew to 3.9 GB without a limit. btrfs compression does not bound growth (compsize of `/var/log` showed 37%, with part of the extents stored uncompressed). bees would not help: journal records are unique, nothing to deduplicate (see `docs/btrfs.md` for the decision on bees).

## Boot

`boot.loader.timeout = 1`: the loader took ~6 s with the default. The menu still opens on a key press, but one second is short through a KVM.

## Removed and disabled

- Hyprland cachix substituter: no flake here has a `hyprland` input, `programs.hyprland` comes from nixpkgs, so the cache only added a lookup per path.
- Firewall ports 8080 and 18789 (no other reference in the repo). The OpenClaw gateway stays reachable over Tailscale (`tailscale0` is a trusted interface).
- `searx.nix` is disabled by commenting out its import, like `bees.nix`. The module, its agenix secret `searx-env` and its entry in `secrets.nix` are kept for a return.

## Backups

The `@root` backup (`btrbk-system`) runs daily at 01:05. It starts alongside the `*:0/10` home timer at times; the backup disk is used by nothing else and local snapshots are instant, so no offset is needed.
