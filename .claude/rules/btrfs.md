---
paths:
  - "system-config/nixos/file-systems.nix"
  - "system-config/nixos/backup.nix"
  - "system-config/nixos/hardware-configuration.nix"
  - "docs/btrfs.md"
  - "scripts/btrfs-*.sh"
---

# Btrfs

- Btrfs (NVMe with subvolumes `@root @home @nix @games @log @nocow`, backup HDD at `/backup`): mounts are in `system-config/nixos/file-systems.nix`, backups in `backup.nix`; decisions, measurements and the runbook are in `docs/btrfs.md`. Settled, not to be reopened: `compress-force=zstd:-1` on the NVMe, `zstd:5` on the HDD; bees stays written but disabled; automount only for the HDD.
  - A filesystem UUID is written once, in its `fileSystems.<mount>.device`; derive it from there everywhere else.
  - tmpfiles rules are skipped below an automount (`/backup`): declare such directories in `mountDirs`, which applies them when the disk is mounted and so cannot create them on the filesystem underneath.
  - Only the owner runs `btrfs`/`btrbk` as root.
