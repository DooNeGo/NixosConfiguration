{
  #networking.networkmanager.enable = true;

  boot.kernel.sysctl."net.ipv4.ip_forward" = true;

#  networking.dhcpcd = {
#    enable = true;
#    wait = "background";
#    extraConfig = ''
#      noarp
#      ipv4
#    '';
#  };

  networking.useNetworkd = true;

  systemd.network = {
    enable = true;
    wait-online.enable = false;
  };
}
