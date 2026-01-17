let
  defaultBtrfsOptions = [ "defaults" "compress=zstd:-5" "noatime" ];
in {
  fileSystems = {    
    "/".options = defaultBtrfsOptions;
    "/nix".options = defaultBtrfsOptions;
    "/boot".options = defaultBtrfsOptions;
    "/boot/EFI".options = [ "defaults" ];
    "/home".options = [ "defaults" "noatime" ];
  };

  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  }; 
}
