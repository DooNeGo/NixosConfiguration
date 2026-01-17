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
        dns = [ "1.1.1.1" "8.8.8.8" "8.8.4.4" ];
      };
    };
  };
}
