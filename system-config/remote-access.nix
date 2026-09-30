{ config, pkgs, pkgs-stable, ... }:
{
  services = {
    tailscale = {
      enable = true;
      extraUpFlags = [ "--accept-dns=false" ];
    };

    sunshine = {
      enable = true;
      package = pkgs-stable.sunshine;
      autoStart = true;
      capSysAdmin = true;
      openFirewall = true;
    };
  };

  networking = {
    nftables.enable = true;
    firewall = {
      trustedInterfaces = [ config.services.tailscale.interfaceName ];
      allowedUDPPorts = [ config.services.tailscale.port ];
    };
  };

  systemd.services.tailscaled.serviceConfig.Environment = [
    "TS_DEBUG_FIREWALL_MODE=nftables"
  ];
}
