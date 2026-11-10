{
  config,
  lib,
  pkgs,
  utils,
  ...
}:
let
  uuidOf = mount: lib.removePrefix "/dev/disk/by-uuid/" config.fileSystems.${mount}.device;
  reclaim = {
    periodic_reclaim = true;
    dynamic_reclaim = true;
  };

  defaultBtrfsOptions = [
    "defaults"
    # Plain compress leaves a file uncompressed when its first extent does not shrink, even if the rest would.
    "compress-force=zstd:-1"
    "noatime"
  ];

  # For mounts the system can run without: a missing disk does not stop the boot and is given up on after 10s, not 90s.
  optionalMount = [
    "nofail"
    "x-systemd.device-timeout=10s"
  ];
in
{
  options.mountDirs = lib.mkOption {
    type = lib.types.attrsOf (lib.types.listOf lib.types.str);
    default = { };
    example."/backup" = [ "0700 root root ." ];
    description = ''
      Directories ("mode user group path", path relative to the mount) created and chmod/chowned each time the
      mount comes up. For automounts: systemd-tmpfiles skips automount points, and a rule applied while the disk is
      missing would create the path on the filesystem underneath.
    '';
  };

  config = {
    fileSystems = {
      "/".options = defaultBtrfsOptions;
      "/nix".options = defaultBtrfsOptions;
      "/home".options = defaultBtrfsOptions;
      "/games".options = defaultBtrfsOptions ++ optionalMount;
      "/var/log" = {
        options = defaultBtrfsOptions;
        neededForBoot = true;
      };
      "/var/lib/nocow".options = defaultBtrfsOptions ++ optionalMount;

      # Top-level subvolume (id 5): btrbk reads every subvolume from here and keeps its .snapshots here.
      "/mnt/btrfs-top".options = defaultBtrfsOptions ++ [ "subvolid=5" ];

      # Backup HDD (sda4, label games_arch). The HDD (~100 MiB/s) is the bottleneck, not the CPU, so compress-force at
      # zstd:5 writes ~2x faster than uncompressed on compressible data and costs nothing on incompressible data
      # (measured, docs/btrfs.md).
      "/backup".options = [
        "defaults"
        "compress-force=zstd:5"
        "noatime"
      ]
      # Mounted on first access, so a disk that shows up after boot needs no manual mount.
      ++ optionalMount
      ++ [ "x-systemd.automount" ];
    };

    # Return mostly-empty data block groups to unallocated space (kernel >= 6.11) so the disk cannot hit ENOSPC with
    # free space stuck in half-empty chunks; dynamic_reclaim scales the threshold with the unallocated space left.
    # This option only reaches filesystems mounted before sysinit: its path units watch sysfs, which sends no inotify
    # events, so a later mount is never noticed. Automounted filesystems are set by btrfs-reclaim-* below.
    boot.kernel.sysfs.fs.btrfs.${uuidOf "/"}.allocation.data = reclaim;

    services = {
      btrfs.autoScrub = {
        enable = true;
        interval = "monthly";
        fileSystems = [
          "/"
          "/backup"
        ];
      };

      # discard=async (the btrfs default since 6.2) already trims freed extents, so the weekly fstrim is redundant.
      fstrim.enable = false;

      # Scrub errors would otherwise only reach the journal.
      failure-notify.units = [ "btrfs-scrub@" ];
    };

    # Root-only: the @root backups hold the agenix host key.
    mountDirs."/backup" = [ "0700 root root ." ];

    systemd.services =
      let
        onMount = mount: {
          wantedBy = [ "${utils.escapeSystemdPath mount}.mount" ];
          bindsTo = [ "${utils.escapeSystemdPath mount}.mount" ];
          after = [ "${utils.escapeSystemdPath mount}.mount" ];
          serviceConfig.Type = "oneshot";
        };
      in
      lib.mapAttrs' (
        mount: dirs:
        lib.nameValuePair "mount-dirs-${utils.escapeSystemdPath mount}" (
          onMount mount
          // {
            description = "Directories and permissions on ${mount}";
            path = [
              pkgs.coreutils
              pkgs.util-linux
            ];
            script = ''
              # Never touch the filesystem underneath the mount point.
              findmnt -n -M ${lib.escapeShellArg mount} -t ${config.fileSystems.${mount}.fsType} >/dev/null
              while read -r mode user group path; do
                install -d -m "$mode" -o "$user" -g "$group" ${lib.escapeShellArg mount}/"$path"
              done <<'EOF'
              ${lib.concatStringsSep "\n" dirs}
              EOF
            '';
          }
        )
      ) config.mountDirs
      // lib.genAttrs' [ "/backup" ] (
        mount:
        lib.nameValuePair "btrfs-reclaim-${utils.escapeSystemdPath mount}" (
          onMount mount
          // {
            description = "Block group reclaim on ${mount}";
            script = lib.concatMapAttrsStringSep "" (name: value: ''
              echo ${if value then "1" else "0"} >/sys/fs/btrfs/${uuidOf mount}/allocation/data/${name}
            '') reclaim;
          }
        )
      );

    systemd.tmpfiles.rules = [
      "d /games 2775 root users -"
      "d /var/lib/nocow 775 root users -"
    ];
  };
}
