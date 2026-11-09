{
  config,
  lib,
  pkgs,
  ...
}:
let
  top = "/mnt/btrfs-top"; # top-level subvolume of the NVMe filesystem, see file-systems.nix
  backupMount = "/backup"; # HDD, see file-systems.nix
  # Created by hand on the HDD, NOT by tmpfiles: with the HDD missing the path would land on the NVMe root and
  # btrbk would receive backups onto the full disk.
  targetDir = "${backupMount}/btrbk";
in
{
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
    # Without the HDD there is no target and btrbk would keep every local snapshot, filling the disk, so the run
    # must fail before btrbk starts. The check triggers the automount. RequiresMountsFor would not do: a device that
    # times out cancels the job without putting the unit into "failed", so nothing would report it. "+" runs the
    # check as root, the btrbk user cannot look into the root-only ${backupMount}.
    services = lib.genAttrs [ "btrbk-home" "btrbk-system" ] (_: {
      unitConfig.RequiresMountsFor = top;
      serviceConfig.ExecStartPre = "+${pkgs.coreutils}/bin/test -d ${targetDir}";
    });

    # The module sets AccuracySec = 10min, which would blur a 10-minute timer.
    timers.btrbk-home.timerConfig.AccuracySec = lib.mkForce "1min";

    tmpfiles.rules = [ "d ${top}/.snapshots 0755 root root -" ];
  };

  assertions = [
    {
      assertion = config.fileSystems ? ${top} && config.fileSystems ? ${backupMount};
      message = "backup.nix needs the mounts ${top} and ${backupMount} (file-systems.nix).";
    }
  ];
}
