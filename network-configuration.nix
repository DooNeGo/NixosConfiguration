{ config, pkgs, ...  }:

{
  networking.useNetworkd = true;

  systemd.network = {
    enable = true;
    wait-online.enable = false;
    networks."10-lan" = {
      matchConfig.Name = "lan"; 
      networkConfig.DHCP = "ipv4";
    };
  };
}
