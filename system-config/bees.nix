{ config, lib, ... }:
let
  btrfsUuid = lib.removePrefix "/dev/disk/by-uuid/" config.fileSystems."/".device;
in
{
  # One instance for the whole filesystem: dedup crosses subvolumes.
  services.beesd.filesystems.nixos = {
    spec = "UUID=${btrfsUuid}";

    # 1.7 TB of unique data counted uncompressed; compressed extents are at most 128 KB, which needs 2-4x the
    # ~128 MB/TB of a plain filesystem (upstream docs/config.md). The table is locked in RAM.
    hashTableSizeMB = 1024;

    verbosity = "info";

    # The unit already runs at Nice=19 / idle IO; this also caps the cores used.
    extraOptions = [
      "--thread-count"
      "4"
      "--loadavg-target"
      "4.0"
    ];
  };
}
