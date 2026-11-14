# sing-box with AmneziaWG and the Tailscale exit node

What was decided and why. The units and rules are in `system-config/nixos/sing-box.nix` and `awg-exit-node.nix`; this file holds what the code does not show.

## Why AmneziaWG sits under sing-box

- The vless `main` instance stopped working; the replacement is a server-issued AmneziaWG `.conf` (agenix: `secrets/awg-main.age`, delivered to `/etc/sing-box/main-awg.conf`). The instance keeps the name `main` and port 2080, so `HTTP(S)_PROXY`, searx and the Nix daemon did not change.
- sing-box has no AmneziaWG outbound, so the kernel module (`wg-quick` with `type = "amneziawg"`) holds the tunnel and sing-box only binds its `proxy` outbound to `awg0`. What sing-box still gives: domain-based routing for `HTTP_PROXY` clients, DNS for proxied domains through the tunnel, and the same instance interface as the vless ones (`credits-*`).
- Fail closed: `bind_interface` makes a matched domain fail when the tunnel is down instead of leaving through `eno1`.
- The server `.conf` is stored verbatim; `prepare-awg.sh` derives the runtime config: it drops `DNS` (would replace the system resolver) and hooks (a third-party file must not run commands as root), puts the routes into table 51820 so `main` stays untouched, and keeps IPv4 only.
- Source-address policy rule `from <tunnel address> lookup 51820` (priority 5000) is what sends sing-box's bound sockets into the tunnel.

## Exit node for the phone

- One AmneziaWG key allows one connection, and both the host and the phone need it. The phone selects this host as a Tailscale exit node and the host forwards that traffic into the same `awg0`: one WireGuard peer, no second key. With a second key, add a second interface and table instead.
- `iif tailscale0 lookup 51820` has priority 5280, after Tailscale's `5270 lookup 52`: tailnet-to-tailnet traffic stays in the tailnet. Packets for the host itself (its tailnet and LAN addresses) hit the `local` table first, so murmur, Sunshine and the headless session work while the exit node is on. Other LAN devices are not reachable through it; add a `192.168.0.0/16` rule before 5280 if that is ever needed.
- A `blackhole default` in table 51820 keeps the phone's traffic from falling through to `main` (the real uplink and address) while `awg0` is down. `awg-exit-node.service` therefore does not depend on `wg-quick-awg0`: the rule and the blackhole stay when the tunnel stops or fails, and only a stop of `awg-exit-node` itself removes them (`wg-quick` deletes only the routes of `awg0`).
- The tunnel is IPv4-only, so forwarded IPv6 from `tailscale0` is rejected (not dropped: a drop makes dual-stack clients wait for a timeout before using IPv4). `awg0` has MTU 1280, so TCP SYN and SYN-ACK are clamped to the route MTU in both directions; masquerade is set on `awg0` explicitly.
- Who may use the exit node is Tailscale policy (admin console, ACL), not repository state. After the first `switch` the exit node has to be approved there once.

## Things to know

- `systemd.network.wait-online` is disabled, so `network-online.target` does not wait for a default route; sing-box logs `missing default interface` at boot and works afterwards. This is cosmetic.
- Renaming an instance renames its `-awg-prepare` unit, so `wg-quick-awg0` restarts on `switch`: the tunnel and the phone's exit node drop for a second.
- Leftovers of a removed instance are not cleaned by `switch` (`/var/lib/sing-box/<name>`, old runtime files in `/etc/sing-box`); only the owner removes them.
- A tunnel address change on the server side needs a restart of `sing-box-main`: the generator bakes the address into `config.json` (`restartTriggers` on the secret does this on `switch`).
