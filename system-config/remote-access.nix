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

  # Expose the OpenClaw gateway WebUI over tailnet HTTPS.
  # Runs as root, so no `tailscale set --operator` is needed.
  # https://nixos.tail416d29.ts.net -> 127.0.0.1:18789
  # (serve config persists in tailscaled state; this oneshot
  # re-applies it idempotently on every boot)
  systemd.services.tailscale-serve-openclaw = {
    description = "tailscale serve: OpenClaw gateway WebUI over tailnet HTTPS";
    after = [ "network-online.target" "tailscaled.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.tailscale}/bin/tailscale serve --bg --https=443 http://127.0.0.1:18789";
    };
  };
}
