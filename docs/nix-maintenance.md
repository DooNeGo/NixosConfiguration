# Nix maintenance: garbage collection, generations, journal

How the Nix store, generations, journal and boot menu are kept in bounds, and why each limit is what it is.

## Garbage collection and generations

- Garbage collection is `programs.nh.clean` (`system-config/shared/nh.nix`, imported by NixOS and nix-darwin), not `nix.gc`. It runs weekly (`nh clean all --keep-since 14d --keep N`): besides the store it removes stale system profile generations and result links.
- `generationsKeep` (default 20) is one number for two places: `nh clean --keep` and `boot.loader.systemd-boot.configurationLimit`. A boot entry whose generation was collected would fail to boot, so the menu never lists more generations than `nh clean` keeps. `--keep-since 14d` is the age limit on top of it.
- Home Manager generations are expired per user by `services.home-manager.autoExpire` (`home-config/shared/auto-expire.nix`, 7 days, systemd user timer on Linux, launchd agent on the Mac). `nh clean` is not relied on for them.
- Unverified without the owner: how `nh clean` behaves on the Mac (its launchd job runs as root and may also clean the profiles of `DooNeGo`).

## nix-daemon environment

- `TMPDIR=/var/tmp`: `/tmp` is a tmpfs of half the RAM (`boot.nix`), too small for CUDA and other large builds. `/var/tmp` lives on `@root`, which is snapshotted and backed up; scratch data of a build running at snapshot time is kept until the snapshot expires. Accepted by the owner.
- Downloads use the system resolver and routes. Destinations covered by a sing-box routing domain use its Fake-IP TUN.

## Journal

`journald.nix`: `SystemMaxUse=500M`, `MaxRetentionSec=1month`. The size limit is what bounds the journal: btrfs compression does not (`/var/log` compresses to about 37%, with part of the extents stored uncompressed) and bees would not help, since journal records are unique (`docs/btrfs.md`, section on bees).

## Boot

`boot.loader.timeout = 1`: the default delay is about 6 s. The menu still opens on a key press, but one second is short through a KVM.

## Disabled on purpose

- No Hyprland cachix substituter: no flake here has a `hyprland` input (`programs.hyprland` comes from nixpkgs), so the cache would only add a lookup per path.
- Firewall ports 8080 and 18789 are closed. The OpenClaw gateway is reachable over Tailscale (`tailscale0` is a trusted interface).
- `bees.nix` is imported nowhere; the module stays for a return.

## Backups

The `@root` backup (`btrbk-system`) runs daily at 01:05. It starts alongside the `*:0/10` home timer at times; the backup disk is used by nothing else and local snapshots are instant, so no offset is needed.
