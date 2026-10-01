{ config, pkgs, pkgs-stable, ... }:
{
  services = {
    tailscale = {
      enable = true;
      extraUpFlags = [ "--accept-dns=false" ];

      # Expose the OpenClaw gateway WebUI over tailnet HTTPS:
      # https://nixos.tail416d29.ts.net -> 127.0.0.1:18789
      # (module wires a root-run `tailscale-serve` oneshot that applies
      # the config idempotently on every boot; no operator needed)
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
