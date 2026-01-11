{
  networking.dhcpcd = {
    enable = true;
    wait = "background";
    extraConfig = ''
      noarp
      ipv4only
      ipv4
    '';
  };

#  networking.useNetworkd = true;

#  systemd.network = {
#    enable = true;
#    wait-online.enable = false;
#  };
}
