let
  defaultBtrfsOptions = [ "defaults" "compress=zstd:-1" "noatime" ];
in {
  fileSystems = {    
    "/".options = defaultBtrfsOptions;
    "/nix".options = defaultBtrfsOptions;
    "/home".options = defaultBtrfsOptions;
    "/games".options = defaultBtrfsOptions;
    "/var/log".options = defaultBtrfsOptions;
    "/var/lib/nocow".options = [ "defaults" "compress=zstd:-1" "nodatacow" "noatime" ];
  };

  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  };

  systemd.tmpfiles.rules = [
    "d /games 2775 root users -"
    "d /var/lib/nocow 775 root users -"
  ];
}
