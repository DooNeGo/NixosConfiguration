{
  config,
  pkgs,
  ...
}:

let
  # Must match `main.awg` in sing-box.nix: the interface and routing table
  # that wg-quick brings up for the AmneziaWG tunnel.
  iface = "awg0";
  table = "51820";

  # After Tailscale's own `5270 lookup 52`, so tailnet-to-tailnet traffic is
  # routed inside the tailnet and only exit-node traffic reaches this rule.
  rulePriority = "5280";

  ip = "${pkgs.iproute2}/bin/ip";
  ts = config.services.tailscale.interfaceName;
  rule = "iif ${ts} lookup ${table} priority ${rulePriority}";
in
{
  assertions = [
    {
      assertion = config.networking.wg-quick.interfaces ? ${iface};
      message = "awg-exit-node.nix expects the wg-quick interface ${iface} (see sing-box.nix)";
    }
  ];

  services.tailscale = {
    useRoutingFeatures = "server";
    extraSetFlags = [ "--advertise-exit-node" ];
  };

  # Packets that arrive from the tailnet and are not for the tailnet or for
  # this host go out through the AWG tunnel. The unit is deliberately not tied to
  # the tunnel's lifecycle: while `awg0` is down, only the blackhole route is left
  # in the table and the traffic is dropped instead of falling through to `main`
  # (the real uplink and address).
  systemd.services.awg-exit-node = {
    description = "Route Tailscale exit-node traffic through ${iface}";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${ip} -4 rule del ${rule} 2>/dev/null || true
      ${ip} -4 rule add ${rule}
      ${ip} -4 route replace blackhole default metric 4000 table ${table}
    '';
    preStop = ''
      ${ip} -4 rule del ${rule} 2>/dev/null || true
      ${ip} -4 route del blackhole default metric 4000 table ${table} 2>/dev/null || true
    '';
  };

  networking.nftables.tables.awg-exit-node = {
    family = "inet";
    content = ''
      chain forward {
        type filter hook forward priority -10; policy accept;
        # the tunnel is IPv4-only: IPv6 from exit-node clients must not leave
        # through the uplink; reject (not drop) so the client falls back to IPv4 at once
        iifname "${ts}" meta nfproto ipv6 oifname != "${ts}" reject with icmpv6 type no-route
        # both directions: the SYN-ACK from the server also needs the lower MSS
        iifname "${iface}" tcp flags syn tcp option maxseg size set rt mtu
        oifname "${iface}" tcp flags syn tcp option maxseg size set rt mtu
      }

      chain postrouting {
        type nat hook postrouting priority srcnat; policy accept;
        iifname "${ts}" oifname "${iface}" masquerade
      }
    '';
  };
}
