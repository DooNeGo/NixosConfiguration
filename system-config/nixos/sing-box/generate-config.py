#!/usr/bin/env python3
"""Generate one instance config.json; all inputs arrive via env (offline)."""
import json
import os
import re


CREDENTIAL = os.environ.get("SING_BOX_CREDENTIAL", "vless-key")
SECRET_FILE = os.path.join(
    os.environ.get("CREDENTIALS_DIRECTORY", "/run/credentials/sing-box.service"),
    CREDENTIAL,
)
OUT_FILE = os.environ.get("SING_BOX_OUT_FILE", "/run/sing-box/config.json")
LISTEN_ADDRESS = os.environ.get("SING_BOX_LISTEN_ADDRESS", "127.0.0.1")
LISTEN_PORT = int(os.environ.get("SING_BOX_LISTEN_PORT", "2080"))
ROUTE_MATCH = os.environ.get("SING_BOX_ROUTE_MATCH", "domain_suffix")
TRANSPORT_OVERRIDE = os.environ.get("SING_BOX_TRANSPORT_OVERRIDE", "")


def _unquote(s):
    # decode %XX escapes (latin-1, replace), matching urllib.parse.unquote on
    # the well-formed values these links carry.
    return re.sub(
        r"%([0-9A-Fa-f]{2})",
        lambda m: bytes.fromhex(m.group(1)).decode("latin-1", "replace"),
        s,
    )


def parse_vless(vless):
    """Parse vless://UUID@host:port?k=v&... without urllib (offline).

    Returns (uuid, host, port, params). `params` maps each query key to a list
    of its values (first value used via q()), matching the old
    urllib.parse.urlparse + parse_qs + q() contract.
    """
    rest = vless[len("vless://"):].split("#", 1)[0]
    at = rest.rfind("@")
    if at == -1:
        raise SystemExit("vless link is missing the uuid@host separator")
    uuid = _unquote(rest[:at])
    hostport = rest[at + 1:]
    qm = hostport.find("?")
    if qm == -1:
        hostport, query = hostport, ""
    else:
        hostport, query = hostport[:qm], hostport[qm + 1:]
    if hostport.startswith("["):
        rb = hostport.find("]")
        host = hostport[1:rb]
        port = hostport[rb + 1:].lstrip(":") or "443"
    else:
        colon = hostport.rfind(":")
        if colon == -1:
            host, port = hostport, "443"
        else:
            host, port = hostport[:colon], hostport[colon + 1:]
    params = {}
    for part in query.split("&"):
        if not part:
            continue
        k, _, v = part.partition("=")
        params.setdefault(k, []).append(_unquote(v))
    return uuid, host.lower(), (port or "443"), params


def q(params, name, default=None):
    vals = params.get(name)
    return vals[0] if vals else default


def load_domains():
    raw = os.environ.get("SING_BOX_PROXY_DOMAINS", "")
    if not raw:
        raise SystemExit("SING_BOX_PROXY_DOMAINS is not set")
    domains = json.loads(raw)
    if not isinstance(domains, list) or not domains:
        raise SystemExit("SING_BOX_PROXY_DOMAINS must be a non-empty JSON array")
    return domains


def read_secret():
    with open(SECRET_FILE, "r", encoding="utf-8") as fh:
        return fh.read().strip()


def read_vless():
    """The runtime key must already be a raw vless:// link (the -fetch oneshot
    guarantees this -- see resolve-credential.sh). No network, no decoding here."""
    raw = read_secret()
    if not raw.startswith("vless://"):
        raise SystemExit(
            "credential is not a vless:// link; the -fetch oneshot failed or the "
            "agenix secret holds an un-fetched https:// URL - run "
            "systemctl start <name>-fetch first"
        )
    return raw


def build_outbound(vless):
    uuid, host, port, params = parse_vless(vless)

    # transport + security from the link's own params; an override pin wins.
    stype = (TRANSPORT_OVERRIDE or q(params, "type", "tcp")).lower()
    security = q(params, "security", "")
    if TRANSPORT_OVERRIDE == "ws":
        stype = "ws"
    elif TRANSPORT_OVERRIDE == "reality":
        security = "reality"
    if not security:
        # fallback for links without security= (reality iff pbk present):
        security = "reality" if q(params, "pbk") else "tls"

    outbound = {
        "type": "vless",
        "tag": "proxy",
        "server": host,
        "server_port": int(port),
        "uuid": uuid,
    }

    # TLS layer -- only when the link uses tls/reality (never for security=none).
    if security in ("tls", "reality"):
        tls = {
            "enabled": True,
            "server_name": q(params, "sni", host),
            "utls": {"enabled": True, "fingerprint": q(params, "fp", "chrome")},
        }
        if security == "reality":
            # reality REQUIRES utls (checks c/e) -- utls is always emitted above.
            tls["reality"] = {
                "enabled": True,
                "public_key": q(params, "pbk", ""),
                "short_id": q(params, "sid", ""),
            }
        outbound["tls"] = tls

    # flow is TCP-only (XTLS Vision: TCP+TLS/REALITY); ws/http/httpupgrade reject it.
    flow = q(params, "flow")
    if flow and stype == "tcp":
        outbound["flow"] = flow

    # transport -- ws (the common non-tcp case). V2Ray schema: type is const
    # "ws" (NOT "websocket"), path=upgrade path, Host goes in headers.
    if stype in ("ws", "http", "httpupgrade"):
        transport = {"type": "ws"}
        path = q(params, "path")
        if path:
            transport["path"] = path
        hosth = q(params, "host")
        if hosth:
            transport["headers"] = {"Host": hosth}
        ed = q(params, "ed") or q(params, "earlyData")
        if ed and ed.isdigit():
            transport["max_early_data"] = int(ed)
        outbound["transport"] = transport
    return outbound


def build_config(domains):
    vless = read_vless()
    return {
        "log": {"level": "warn", "timestamp": True},
        "inbounds": [
            {
                "type": "mixed",
                "tag": "mixed-in",
                "listen": LISTEN_ADDRESS,
                "listen_port": LISTEN_PORT,
            }
        ],
        "outbounds": [
            build_outbound(vless),
            {"type": "direct", "tag": "direct"},
        ],
        "route": {
            "rules": [
                {"action": "sniff"},
                {ROUTE_MATCH: domains, "action": "route", "outbound": "proxy"},
            ],
            "final": "direct",
            "auto_detect_interface": True,
        },
    }


def main():
    config = build_config(load_domains())
    os.makedirs(os.path.dirname(OUT_FILE), exist_ok=True)
    tmp = OUT_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(config, fh, indent=2)
        fh.write("\n")
    os.chmod(tmp, 0o600)
    os.replace(tmp, OUT_FILE)


if __name__ == "__main__":
    main()
