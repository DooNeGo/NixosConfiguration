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
      settings.capture = "wlr";
    };
  };

  # Hyprland holds the X11 socket and starts Xwayland lazily; if that fails the
  # socket backlog fills and libEGL_nvidia's XOpenDisplay blocks Sunshine at startup.
  systemd.user.services.sunshine.serviceConfig.UnsetEnvironment = [ "DISPLAY" ];

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
