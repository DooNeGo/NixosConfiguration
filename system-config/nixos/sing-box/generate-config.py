#!/usr/bin/env python3
"""Generate one instance config.json; all inputs arrive via env (offline)."""

import json
import os

from kinds import awg, vless

KINDS = {"awg": awg, "vless": vless}


def load_domains(env):
    raw = env.get("SING_BOX_PROXY_DOMAINS", "")
    if not raw:
        raise SystemExit("SING_BOX_PROXY_DOMAINS is not set")
    domains = json.loads(raw)
    if not isinstance(domains, list) or not domains:
        raise SystemExit("SING_BOX_PROXY_DOMAINS must be a non-empty JSON array")
    return domains


def build_config(env, domains):
    kind = env.get("SING_BOX_KIND")
    if not kind:
        raise SystemExit("SING_BOX_KIND is not set")
    if kind not in KINDS:
        raise SystemExit(f"unknown SING_BOX_KIND {kind!r}")
    result = KINDS[kind].build(env)
    tun = json.loads(env.get("SING_BOX_TUN") or "null")
    config = build_base_config(env, domains, result["outbound"])
    if result.get("dns") is not None:
        config["dns"] = result["dns"]
    if result.get("default_domain_resolver") is not None:
        config["route"]["default_domain_resolver"] = result["default_domain_resolver"]
    if tun:
        add_tun(config, tun, domains)
    return config


def add_tun(config, tun, domains):
    """TUN inbound with fake-IP for the proxied domains only."""
    dns = config.setdefault("dns", {"servers": [{"type": "local", "tag": "dns-local"}], "final": "dns-local"})
    config["route"].setdefault("default_domain_resolver", "dns-local")
    dns["servers"].append({"type": "fakeip", "tag": "dns-fakeip", "inet4_range": tun["fakeRange"]})
    # Only queries that arrive through the TUN get fake answers; the outbound's
    # own lookups keep the kind's resolvers. First, so no rule of the kind
    # shadows it.
    dns.setdefault("rules", []).insert(
        0, {"inbound": ["tun-in"], "domain_suffix": domains, "action": "route", "server": "dns-fakeip"}
    )
    config["inbounds"].append(
        {
            "type": "tun",
            "tag": "tun-in",
            "interface_name": tun["interface"],
            "address": [tun["address"]],
            "dns_address": tun["dnsAddress"],
            "auto_route": False,
        }
    )
    rules = config["route"]["rules"]
    sniff = next((i for i, rule in enumerate(rules) if rule.get("action") == "sniff"), None)
    if sniff is None:
        raise SystemExit("the base config has no sniff rule to place hijack-dns after")
    rules.insert(sniff + 1, {"protocol": "dns", "action": "hijack-dns"})
    # a restart keeps the fake address of a name that a client still holds
    config["experimental"] = {"cache_file": {"enabled": True, "store_fakeip": True}}


def build_base_config(env, domains, proxy):
    # Fail closed for every kind: matched domains have exactly one way out
    # ("proxy"); there is no fallback outbound if it is down.
    route_match = env.get("SING_BOX_ROUTE_MATCH", "domain_suffix")
    return {
        "log": {"level": "warn", "timestamp": True},
        "inbounds": [
            {
                "type": "mixed",
                "tag": "mixed-in",
                "listen": env.get("SING_BOX_LISTEN_ADDRESS", "127.0.0.1"),
                "listen_port": int(env.get("SING_BOX_LISTEN_PORT", "2080")),
            }
        ],
        "outbounds": [
            proxy,
            {"type": "direct", "tag": "direct"},
        ],
        "route": {
            "rules": [
                {"action": "sniff"},
                {route_match: domains, "action": "route", "outbound": "proxy"},
            ],
            "final": "direct",
            "auto_detect_interface": True,
        },
    }


def main():
    env = os.environ
    config = build_config(env, load_domains(env))
    out_file = env.get("SING_BOX_OUT_FILE", "/run/sing-box/config.json")
    os.makedirs(os.path.dirname(out_file), exist_ok=True)
    tmp = out_file + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(config, fh, indent=2)
        fh.write("\n")
    os.chmod(tmp, 0o600)
    os.replace(tmp, out_file)


if __name__ == "__main__":
    main()
