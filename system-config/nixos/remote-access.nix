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

  # The logind ACL on /dev/uinput goes to the active seat0 session, which is the SDDM greeter next to the headless
  # session, so Sunshine's virtual keyboard and mouse need the group.
  users.users.mathew.extraGroups = [ "uinput" ];

  networking = {
    nftables.enable = true;
    firewall = {
      trustedInterfaces = [ config.services.tailscale.interfaceName ];
      allowedUDPPorts = [ config.services.tailscale.port ];
    };
  };

  systemd = {
    # The SDDM greeter session also reaches graphical-session.target; a Sunshine started as sddm holds the ports.
    user.services.sunshine.unitConfig.ConditionUser = "mathew";

    services = {
      tailscaled.serviceConfig.Environment = [
        "TS_DEBUG_FIREWALL_MODE=nftables"
      ];

      # tailscaled counts as started before it has joined the tailnet, and `serve set-config` then fails with NoState.
      tailscale-serve.serviceConfig = {
        Restart = "on-failure";
        RestartSec = "10s";
      };
    };
  };
}
