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
        services = {
          openclaw-webui.endpoints = {
            "tcp:80" = "http://127.0.0.1:19001";
            "tcp:443" = "https://127.0.0.1:19001";
            #"tcp:444" = "http://127.0.0.1:18789";
          };
        };
      };
    };

    sunshine = {
      enable = true;
      autoStart = true;
      capSysAdmin = true;
      openFirewall = true;
      settings = {
        capture = "wlr";
        encoder = "nvenc";
        nvenc_preset = 4;
        min_log_level = 3;
      };
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
