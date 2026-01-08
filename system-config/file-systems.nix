let
  defaultBtrfsOptions = [ "defaults" "compress=zstd:-5" "noatime" ];
in {
  fileSystems = {    
    "/".options = defaultBtrfsOptions;
    "/nix".options = defaultBtrfsOptions;
    "/boot".options = defaultBtrfsOptions;
    "/home".options = [ "defaults" "noatime" "data=writeback" "journal_async_commit" "commit=10" ];
  };    
}
