{
  boot.kernel.sysctl."net.ipv4.ip_forward" = true;

  networking = {
    useNetworkd = true;
    useDHCP = false;

    firewall = {
      allowedTCPPorts = [
        57621
        8080
        18789
      ];
      allowedUDPPorts = [ 5353 ];
    };
  };

  systemd.network = {
    enable = true;
    wait-online.enable = false;

    networks."10-lan" = {
      matchConfig.Name = "en*";
      networkConfig.DHCP = "yes";
    };
  };
}
