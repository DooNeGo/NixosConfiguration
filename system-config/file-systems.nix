{ config, lib, ... }:
let
  btrfsUuid = lib.removePrefix "/dev/disk/by-uuid/" config.fileSystems."/".device;

  defaultBtrfsOptions = [
    "defaults"
    "compress=zstd:-1"
    "noatime"
  ];
in
{
  fileSystems = {
    "/".options = defaultBtrfsOptions;
    "/nix".options = defaultBtrfsOptions;
    "/home".options = defaultBtrfsOptions;
    "/games".options = defaultBtrfsOptions;
    "/var/log" = {
      options = defaultBtrfsOptions;
      neededForBoot = true;
    };
    "/var/lib/nocow".options = defaultBtrfsOptions;
  };

  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  };

  # Return mostly-empty data block groups to unallocated space (kernel >= 6.11) so the disk cannot hit ENOSPC with
  # free space stuck in half-empty chunks; dynamic_reclaim scales the threshold with the unallocated space left.
  boot.kernel.sysfs.fs.btrfs.${btrfsUuid}.allocation.data = {
    periodic_reclaim = true;
    dynamic_reclaim = true;
  };

  # discard=async (the btrfs default since 6.2) already trims freed extents, so the weekly fstrim is redundant.
  services.fstrim.enable = false;

  systemd.tmpfiles.rules = [
    "d /games 2775 root users -"
    "d /var/lib/nocow 775 root users -"
  ];
}
