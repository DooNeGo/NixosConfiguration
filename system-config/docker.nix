{
  virtualisation.docker = {
    enable = false;
    enableOnBoot = false;
    storageDriver = "btrfs";

    rootless = {
      enable = true;
      setSocketVariable = true;
      daemon.settings = {
        iptables = true;
        storage-driver = "btrfs";
        dns = [ "1.1.1.1" "8.8.8.8" "8.8.4.4" ];
      };
    };
  };
}
