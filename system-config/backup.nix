{ config, lib, ... }:
let
  top = "/mnt/btrfs-top"; # top-level subvolume of the NVMe filesystem, see file-systems.nix
  backupMount = "/backup"; # HDD (sda4, label games_arch)
  backupUuid = "66a4672a-820c-440c-9f9a-6b7b52c4e434";
  # Created by hand on the HDD, NOT by tmpfiles: with the HDD missing the path would land on the NVMe root and
  # btrbk would receive backups onto the full disk.
  targetDir = "${backupMount}/btrbk";
in
{
  fileSystems.${backupMount} = {
    device = "/dev/disk/by-uuid/${backupUuid}";
    fsType = "btrfs";
    # nofail + short timeout: a missing HDD must not hold up boot. The HDD (~100 MiB/s) is the bottleneck, not the CPU,
    # so compress-force at zstd:5 writes ~2x faster than uncompressed on compressible data and costs nothing on
    # incompressible data (measured, docs/btrfs.md).
    options = [
      "defaults"
      "compress-force=zstd:5"
      "noatime"
      "nofail"
      "x-systemd.device-timeout=10s"
    ];
  };

  # Both are applied when the disk appears (path watcher / mount dependency), so a missing HDD costs nothing.
  services.btrfs.autoScrub.fileSystems = [ backupMount ];
  boot.kernel.sysfs.fs.btrfs.${backupUuid}.allocation.data = {
    periodic_reclaim = true;
    dynamic_reclaim = true;
  };

  # @home often, @root once a day; /games, /nix, @log and /var/lib/nocow are not backed up. Details: docs/btrfs.md.
  services.btrbk.instances =
    let
      mkInstance =
        {
          onCalendar,
          lock,
          localMin,
          targetPreserve,
          subvolumes,
        }:
        {
          inherit onCalendar;
          settings = {
            lockfile = "/var/lib/btrbk/${lock}.lock";
            timestamp_format = "long"; # minute resolution, needed for sub-daily snapshots
            snapshot_dir = ".snapshots"; # relative to the volume (top-level); created by tmpfiles below
            snapshot_create = "onchange"; # no new snapshot when the subvolume did not change
            incremental = "yes";
            snapshot_preserve_min = localMin; # local snapshots younger than this are never deleted
            snapshot_preserve = "no";
            target_preserve_min = "no"; # the HDD keeps exactly what target_preserve says
            target_preserve = targetPreserve;
            volume.${top} = {
              target = targetDir;
              subvolume = lib.genAttrs subvolumes (_: { });
            };
          };
        };
    in
    {
      home = mkInstance {
        onCalendar = "*:0/10";
        lock = "home";
        localMin = "2h";
        targetPreserve = "24h 14d 8w 6m";
        subvolumes = [ "@home" ];
      };

      system = mkInstance {
        onCalendar = "*-*-* 04:05:00";
        lock = "system";
        localMin = "2d";
        targetPreserve = "14d 8w 6m";
        subvolumes = [ "@root" ];
      };
    };

  systemd = {
    # Without the HDD there is no target and btrbk would keep every local snapshot, filling the disk: skip the run.
    services = lib.genAttrs [ "btrbk-home" "btrbk-system" ] (_: {
      unitConfig = {
        ConditionPathIsMountPoint = backupMount;
        RequiresMountsFor = top;
      };
    });

    # The module sets AccuracySec = 10min, which would blur a 10-minute timer.
    timers.btrbk-home.timerConfig.AccuracySec = lib.mkForce "1min";

    tmpfiles.rules = [ "d ${top}/.snapshots 0755 root root -" ];
  };

  assertions = [
    {
      assertion = config.fileSystems ? ${top};
      message = "backup.nix needs the top-level btrfs mount ${top} (file-systems.nix).";
    }
  ];
}
