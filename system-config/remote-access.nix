{
  config,
  pkgs,
  pkgs-stable,
  ...
}:
{
  services = {
    tailscale = {
      enable = true;
      serve = {
        enable = true;
        services.openclaw-webui = {
          endpoints = {
            "tcp:443" = "http://127.0.0.1:18789";
          };
        };
      };
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
