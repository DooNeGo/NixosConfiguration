{
  config,
  lib,
  pkgs,
  ...
}:

let
  exit = config.services.sing-box-tunnels.exitTunnel;

  # After Tailscale's own `5270 lookup 52`, so tailnet-to-tailnet traffic is
  # routed inside the tailnet and only exit-node traffic reaches this rule.
  rulePriority = "5280";

  # Between Tailscale's 5270 and the exit-node rule. The exit node answers DNS for its clients through
  # resolved, which gives a proxied name a fake address; that traffic goes to sing-box (table main
  # routes the range into its TUN), not into the tunnel.
  fakeRulePriority = "5275";

  ip = "${pkgs.iproute2}/bin/ip";
  ts = config.services.tailscale.interfaceName;
in
{
  config = lib.mkIf (exit != null) (
    let
      iface = exit.interface;
      table = toString exit.table;
      rule = "iif ${ts} lookup ${table} priority ${rulePriority}";
      fakeRules = map (
        range: "iif ${ts} to ${range} lookup main priority ${fakeRulePriority}"
      ) config.services.sing-box-tunnels.fakeRanges;
      addRules = lib.concatMapStringsSep "\n" (
        r: "${ip} -4 rule del ${r} 2>/dev/null || true\n${ip} -4 rule add ${r}"
      ) fakeRules;
      delRules = lib.concatMapStringsSep "\n" (r: "${ip} -4 rule del ${r} 2>/dev/null || true") fakeRules;
    in
    {
      assertions = [
        {
          assertion = config.networking.wg-quick.interfaces ? ${iface};
          message = "awg-exit-node.nix: the exit tunnel ${iface} has no networking.wg-quick interface (see sing-box.nix)";
        }
      ];

      # Packets that arrive from the tailnet and are not for the tailnet or for
      # this host go out through the tunnel. The unit is deliberately not tied to
      # the tunnel's lifecycle: while `${iface}` is down, only the blackhole route is left
      # in the table and the traffic is dropped instead of falling through to `main`
      # (the real uplink and address).
      systemd.services.awg-exit-node = {
        description = "Route Tailscale exit-node traffic through ${iface}";
        wantedBy = [ "multi-user.target" ];
        # networkd removes routes it did not configure when it starts, which took the blackhole after a boot
        after = [ "systemd-networkd.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          ${ip} -4 rule del ${rule} 2>/dev/null || true
          ${ip} -4 rule add ${rule}
          ${addRules}
          ${ip} -4 route replace blackhole default metric 4000 table ${table}
        '';
        preStop = ''
          ${ip} -4 rule del ${rule} 2>/dev/null || true
          ${delRules}
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
  );
}
