{
  virtualisation.docker = {
    enable = false;
    enableOnBoot = false;
    storageDriver = "btrfs";

    rootless = {
      enable = true;
      setSocketVariable = true;
    };
  };
}
