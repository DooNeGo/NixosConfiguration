{ config, lib, ... }:
let
  top = "/mnt/btrfs-top"; # top-level subvolume of the NVMe filesystem, see file-systems.nix
  backupMount = "/backup"; # HDD (sda4, label games_arch)
  # Created by hand on the HDD once (`sudo mkdir /backup/btrbk`), deliberately NOT by tmpfiles: if the HDD
  # is missing, this path would otherwise land on the NVMe root and btrbk would receive backups onto the full disk.
  targetDir = "${backupMount}/btrbk";
in
{
  fileSystems.${backupMount} = {
    device = "/dev/disk/by-uuid/66a4672a-820c-440c-9f9a-6b7b52c4e434";
    fsType = "btrfs";
    # nofail + short timeout: a missing/slow HDD must not hold up boot. The HDD is not latency critical, so zstd:3
    # (better ratio than the NVMe's -1) is cheap here.
    options = [
      "defaults"
      "compress=zstd:3"
      "noatime"
      "nofail"
      "x-systemd.device-timeout=10s"
    ];
  };

  # Backed up: @home (a snapshot every 10 minutes when it changed, kept locally for 2 hours as a quick undo window)
  # and @root (once a day). The HDD receives about one snapshot per hour of @home and keeps 24 hourly,
  # 14 daily, 8 weekly and 6 monthly backups; the system subvolumes keep 14 daily, 8 weekly and 6 monthly.
  # /games, /nix and the logs (@log) are not backed up, nor is /var/lib/nocow. Explanation of every line:
  # docs/btrfs.md. Two instances because @home is snapshotted often and @root only once a day.
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
      unitConfig.ConditionPathIsMountPoint = backupMount;
    });

    # The module sets AccuracySec = 10min, which would let a 10-minute timer drift by a whole period.
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
