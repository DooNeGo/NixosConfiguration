"""kind = "awg": traffic leaves through a system AmneziaWG interface that the
NixOS module brings up; sing-box only binds its sockets to it."""

import re


def read_address(interface, addr_file):
    """Tunnel IPv4 published by the -awg-prepare oneshot (not a secret)."""
    if not interface or not addr_file:
        raise SystemExit("kind=awg needs SING_BOX_AWG_INTERFACE and SING_BOX_AWG_ADDR_FILE")
    try:
        with open(addr_file, encoding="utf-8") as fh:
            addr = fh.read().strip()
    except OSError as exc:
        raise SystemExit(f"cannot read {addr_file} ({exc}); the -awg-prepare oneshot has not run") from exc
    if not re.fullmatch(r"\d{1,3}(\.\d{1,3}){3}", addr):
        raise SystemExit(f"{addr_file} does not hold an IPv4 address")
    return addr


def build(env):
    interface = env.get("SING_BOX_AWG_INTERFACE", "")
    addr = read_address(interface, env.get("SING_BOX_AWG_ADDR_FILE", ""))
    # bind_interface: fail closed (ENODEV) when the tunnel is down.
    # inet4_bind_address: makes the `from <addr> lookup <table>` rule match.
    # domain_resolver: proxied domains resolve through the tunnel, IPv4 only.
    outbound = {
        "type": "direct",
        "tag": "proxy",
        "bind_interface": interface,
        "inet4_bind_address": addr,
        "domain_resolver": {"server": "dns-tunnel", "strategy": "ipv4_only"},
    }
    dns = {
        "servers": [
            {
                "type": "udp",
                "tag": "dns-tunnel",
                "server": env.get("SING_BOX_TUNNEL_DNS", "1.1.1.1"),
                "detour": "proxy",
            },
            {"type": "local", "tag": "dns-local"},
        ],
        "final": "dns-local",
    }
    # everything that is not the proxy outbound keeps the system resolver
    return {"outbound": outbound, "dns": dns, "default_domain_resolver": "dns-local"}
