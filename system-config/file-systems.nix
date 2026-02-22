let
  defaultBtrfsOptions = [ "defaults" "compress=zstd:-1" "noatime" ];
in {
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

  services.beesd.filesystems = {
    root = {
      spec = "LABEL=NixOS";
      hashTableSizeMB = 2048;
      verbosity = "crit";
      extraOptions = [ "--loadavg-target" "5.0" ];
  };
};

  systemd.tmpfiles.rules = [
    "d /games 2775 root users -"
    "d /var/lib/nocow 775 root users -"
  ];
}
