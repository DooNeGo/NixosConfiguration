{
  config,
  ...
}:
{
  services.tailscale = {
    enable = true;
    # Forwarding for the exit node; the routing into awg0 is in awg-exit-node.nix.
    useRoutingFeatures = "server";
    extraSetFlags = [ "--advertise-exit-node" ];
    serve = {
      enable = true;
      services = {
        openclaw-webui.endpoints = {
          "tcp:80" = "http://127.0.0.1:19001";
          "tcp:443" = "https://127.0.0.1:19001";
        };
      };
    };
  };

  networking.firewall = {
    trustedInterfaces = [ config.services.tailscale.interfaceName ];
    allowedUDPPorts = [ config.services.tailscale.port ];
  };

  systemd.services = {
    tailscaled.serviceConfig.Environment = [
      "TS_DEBUG_FIREWALL_MODE=nftables"
    ];

    # tailscaled counts as started before it has joined the tailnet, and `serve set-config` then fails with NoState.
    tailscale-serve.serviceConfig = {
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };
}
