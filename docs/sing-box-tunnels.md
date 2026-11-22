# sing-box tunnels and the Tailscale exit node

How the tunnels and the exit node work and why. The units and rules are in `system-config/nixos/sing-box.nix`, `awg-exit-node.nix` and, for the Tailscale service and the `--advertise-exit-node` flag, `tailscale.nix`; this file holds what the code does not show.

## Why AmneziaWG sits under sing-box

- The `main` instance reaches the internet through a server-issued AmneziaWG `.conf` (agenix: `secrets/awg-main.age`, delivered to `/etc/sing-box/main-awg.conf`). It listens on port 2080, which `HTTP(S)_PROXY` and the Nix daemon use.
- sing-box has no AmneziaWG outbound (upstream closed the request as not planned, and the nixpkgs build has no `with_awg`), so the kernel module (`wg-quick` with `type = "amneziawg"`) holds the tunnel and sing-box only binds its `proxy` outbound to `awg0`. What sing-box still gives: domain-based routing for `HTTP_PROXY` clients, DNS for proxied domains through the tunnel, and the same instance interface as the vless one (`credits`).
- Fail closed: `bind_interface` makes a matched domain fail when the tunnel is down instead of leaving through `eno1`.
- The server `.conf` is stored verbatim; `prepare-awg.sh` derives the runtime config: it drops `DNS` (would replace the system resolver) and hooks (a third-party file must not run commands as root), puts the routes into table 51820 so `main` stays untouched, and keeps IPv4 only.
- Source-address policy rule `from <tunnel address> lookup 51820` (priority 5000) is what sends sing-box's bound sockets into the tunnel.

## Kinds: one definition per tunnel kind

`sing-box.nix` holds `instances` (the one attrset to edit), the checks common to all kinds, the main unit `sing-box-<name>`, the user and the merge. Everything that differs per kind is in `sing-box/kinds/<kind>.nix` (a plain function, not a module) and `sing-box/kinds/<kind>.py`; `generate-config.py` keeps the shared part of `config.json` and the `KINDS` registry. The generator is copied (`install -D`) into one store directory, because Python imports `kinds` from the real directory of the script.

A kind file takes `{ pkgs, lib, name, inst, secretFile, shared, ... }` (`secretFile` is the agenix file, `shared` the common helpers) and returns any of these; the dispatcher fills the rest with defaults:

| Field | Meaning |
|---|---|
| `services`, `timers` | units the kind owns, keyed by unit name; may extend a generated one (`wg-quick-<iface>`) |
| `extraConfig` | other NixOS config of the kind, merged with `lib.mkMerge` |
| `deps`, `restartTriggers` | added to `wants`/`after` and `restartTriggers` of `sing-box-<name>` |
| `environment`, `serviceConfig` | additions to the main unit (`SING_BOX_<KIND>_*`, `LoadCredential`) |
| `failureUnits` | names for `services.failure-notify.units` |
| `exitTunnel` | `null`, or `{ interface, table }` when the kind owns a kernel interface and a table |
| `claims` | values that must differ between instances (`interface`, `table`) |
| `assertions` | kind-specific checks with messages |

The Python side exposes `build(env)` returning `{ outbound, dns, default_domain_resolver }` (`None` where the kind adds nothing).

Adding a kind: a line in `kindFiles` of `sing-box.nix`, `kinds/<kind>.nix`, `kinds/<kind>.py` with an entry in `KINDS`, and `kinds/test_<kind>.py`. A test fails when `kindFiles`, `kinds/*.nix`, `kinds/*.py` and `KINDS` disagree; a kind that returns a field not in the table is an evaluation error. Unit names are fixed in the kind file once; `deps` and `failureUnits` use the same names, and the box module disables some of them by name.

## Accepted secret formats

- `awg-<name>.age` holds either the server `.conf` or an Amnezia `vpn://` string (the share string of the Amnezia app). `prepare-awg.sh` takes the first non-blank line: with the `vpn://` prefix the string goes through `sing-box/decode-vpn.py awg` (stdin only), anything else is used as a `.conf`. From there on both take the same path, so the same tunnel gives the same runtime config either way.
- A `vpn://` string is base64url of a Qt `qCompress` blob (4-byte big-endian length, then zlib) holding JSON. `containers[]` lists the containers; the container of `amnezia-awg` and `amnezia-awg2` keeps the `.conf` text in `awg.last_config`, which is itself a JSON string with the text in its `config` field. The decoder uses that text only and fails when it is missing: it does not rebuild a config from the other fields of the JSON, since nothing could check such a config.
- Container selection: `default_container` when it is an AmneziaWG container; otherwise the only AmneziaWG container; otherwise an error (none, or several without a default among them). A string whose default is another protocol still feeds an `awg` instance if it carries exactly one AmneziaWG container.
- The decoder rejects a `PrivateKey` that is an unreplaced template placeholder, a payload over 1 MiB after decompression, and a length header that does not match. It never prints values from the string; to see which keys a string carries (for example the AWG 2.0 `S3`, `S4`, `I1`-`I5`) run `decode-vpn.py inspect < string`: it prints key paths and types, never values.
- Whether the pinned kernel module and `amneziawg-tools` accept every AWG 2.0 key was checked only against the upstream master sources, not against the tags in nixpkgs; a rejected key shows as a failed `wg-quick-awg0`.
- `vless-<name>.age` may hold the `vpn://` string of an `amnezia-xray` container: `resolve-credential.sh` runs `decode-vpn.py xray`, which prints one `vless://` link for `generate-config.py` (its layout, with `last_config` as an object and the default container named `defaultContainer`, was read off a real string with `inspect`). Only `tcp` (`raw` in the Amnezia app) with `reality` is accepted, with or without `xtls-rprx-vision`, because that is what `generate-config.py` turns into an outbound correctly. `xhttp`, mKCP, grpc, ws, plain tls, vless encryption, header obfuscation and a missing public key are refused with a message, since `generate-config.py` would build a wrong outbound for them without an error. `spiderX` is dropped with a warning. An upstream sing-box build has no XHTTP or mKCP transport; they would need a separate `xray` process.
- OpenVPN, Cloak and Shadowsocks containers of a `vpn://` string are not read yet: there was no real string to check their layout against. sing-box 1.14 has a native `openvpn-client` endpoint, which would make a system OpenVPN client unnecessary.
- `-awg-prepare` runs as root on a string that comes from outside, so its unit is sandboxed (no network, read-only system, private `/tmp`; the runtime directory stays writable) and its failure is reported through `failure-notify`.

## Data path

- A client that honours `HTTP(S)_PROXY` connects to sing-box on 127.0.0.1. sing-box ends that TCP connection, matches the domain from the proxy request (or the sniffed name), and opens a new socket: bound to `awg0` and its address for a matched domain, or through `eno1` for the rest. This is the only place where traffic is re-terminated in user space; the browser's own DoH does not matter on this path because the name travels in the `CONNECT` request.
- Traffic that does not use the proxy never reaches sing-box and leaves through `eno1` unchanged.
- The exit-node path (below) is plain kernel forwarding from `tailscale0` into the tunnel; sing-box is not on it.

## Exit node for the phone

- One AmneziaWG key allows one connection, and both the host and the phone need it. The phone selects this host as a Tailscale exit node and the host forwards that traffic into the same `awg0`: one WireGuard peer, no second key. With a second key, add a second interface and table instead.
- The instance that carries the exit node sets `exitNode = true` in `instances` (only a kind that returns `exitTunnel`, today `awg`; at most one: a failed assertion names the offenders). `sing-box.nix` derives the interface and table into `services.sing-box-tunnels.exitTunnel`, and `awg-exit-node.nix` and `tailscale.nix` read only that option. A kind that owns a kernel interface and a table returns `exitTunnel` from its definition (see below); any other kind refuses `exitNode` through an assertion.
- Without such an instance the module adds no rule, blackhole or nft table, and `tailscale.nix` sets `--advertise-exit-node=false`: the flags of `tailscale set` are sticky, so only the explicit false form withdraws an earlier advertisement.
- `iif tailscale0 lookup <table>` has priority 5280, after Tailscale's `5270 lookup 52`: tailnet-to-tailnet traffic stays in the tailnet. Packets for the host itself (its tailnet and LAN addresses) hit the `local` table first, so murmur, Sunshine and the headless session work while the exit node is on. Other LAN devices are not reachable through it; add a `192.168.0.0/16` rule before 5280 if that is ever needed. Community reports say the order of Tailscale's own rules (5210-5270) can change between boots with the start order of services; check `ip rule` after a reboot.
- A `blackhole default` in the table keeps the phone's traffic from falling through to `main` (the real uplink and address) while the tunnel is down. `awg-exit-node.service` therefore does not depend on `wg-quick-<interface>`: the rule and the blackhole stay when the tunnel stops or fails, and only a stop of `awg-exit-node` itself removes them (`wg-quick` deletes only the routes of the interface).
- The tunnel is IPv4-only, so forwarded IPv6 from `tailscale0` is rejected (not dropped: a drop makes dual-stack clients wait for a timeout before using IPv4). `awg0` has MTU 1280, so TCP SYN and SYN-ACK are clamped to the route MTU in both directions; masquerade is set on the tunnel interface explicitly.
- Who may use the exit node is Tailscale policy (admin console, ACL), not repository state. After the first `switch` the exit node has to be approved there once.

## Things to know

- `systemd.network.wait-online` is disabled, so `network-online.target` does not wait for a default route; sing-box logs `missing default interface` at boot and works afterwards. This is cosmetic.
- `awg-exit-node.service` starts before `systemd-networkd` at boot, and networkd removes routes it did not configure at its start: with the default `ManageForeignRoutes` the blackhole was missing after a reboot (a manual restart of the unit brought it back). The unit is therefore ordered after `systemd-networkd.service`; `ip -4 route show table <table>` must list the blackhole after a reboot, and if it does not, `ManageForeignRoutes=false` in `network.nix` is the broader fix that was verified.
- Renaming an instance renames its `-awg-prepare` unit, so `wg-quick-awg0` restarts on `switch`: the tunnel and the phone's exit node drop for a second. Changing the decoder or `prepare-awg.sh` restarts them the same way.
- Leftovers of a removed instance are not cleaned by `switch` (`/var/lib/sing-box/<name>`, old runtime files in `/etc/sing-box`); only the owner removes them.
- A tunnel address change on the server side needs a restart of `sing-box-main`: the generator bakes the address into `config.json` (`restartTriggers` on the secret does this on `switch`).
- Tests of the decoder and of `prepare-awg.sh` on synthetic strings: `python3 -B -m unittest discover -s system-config/nixos/sing-box -p 'test_*.py'`. The box disables these units, so the sandbox of `-awg-prepare` and the exit-node unit are exercised only by the owner's `switch`.
