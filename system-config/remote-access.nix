{
  config,
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
        lan_encryption_mode = 0;
        wan_encryption_mode = 1;
        csrf_allowed_origins = "https://nixos,https://100.113.78.93";
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

  # tailscaled counts as started before it has joined the tailnet, and `serve set-config` then fails with NoState.
  systemd.services.tailscale-serve.serviceConfig = {
    Restart = "on-failure";
    RestartSec = "10s";
  };
}
