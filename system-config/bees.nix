{ config, lib, ... }:
let
  btrfsUuid = lib.removePrefix "/dev/disk/by-uuid/" config.fileSystems."/".device;
in
{
  # Offline block-level deduplication for the whole btrfs filesystem (one instance: dedup crosses subvolumes).
  # Runbook and measurement steps: docs/btrfs.md.
  services.beesd.filesystems.nixos = {
    spec = "UUID=${btrfsUuid}";

    # 16 bytes per block. Upstream (docs/config.md): ~128 MB per TB of unique data for a plain filesystem, and a
    # compressed one needs 2-4x more because compressed extents are at most 128 KB. Unique data is counted
    # uncompressed: 1.7 TB here (compsize, 2026-11), so 0.4-0.9 GB; 1 GB is on the safe side and halving or
    # doubling works almost as well. The table is
    # locked in RAM (MemoryMin/LimitMEMLOCK = this value).
    hashTableSizeMB = 1024;

    verbosity = "info";

    # The shipped unit already runs at Nice=19 / idle IO class; these keep it from using every core.
    extraOptions = [
      "--thread-count"
      "4"
      "--loadavg-target"
      "4.0"
    ];
  };
}
