{
  #networking.networkmanager.enable = true;

  boot.kernel.sysctl."net.ipv4.ip_forward" = true;

  networking.dhcpcd = {
    enable = true;
    wait = "background";
    extraConfig = ''
      noarp
      ipv4
    '';
  };

#  networking = {
#    useNetworkd = true;
#    useDHCP = false;
#  };
#
#  systemd.network = {
#    enable = true;
#    wait-online.enable = false;
#
#    networks."10-lan" = {
#      matchConfig.Name = "en*";
#      networkConfig.DHCP = "yes";
#    };
#  };
}
