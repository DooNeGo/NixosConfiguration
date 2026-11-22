"""kind = "vless": the outbound is built from the vless:// runtime key."""

import os
import re


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
    rest = vless[len("vless://") :].split("#", 1)[0]
    at = rest.rfind("@")
    if at == -1:
        raise SystemExit("vless link is missing the uuid@host separator")
    uuid = _unquote(rest[:at])
    hostport = rest[at + 1 :]
    qm = hostport.find("?")
    if qm == -1:
        hostport, query = hostport, ""
    else:
        hostport, query = hostport[:qm], hostport[qm + 1 :]
    if hostport.startswith("["):
        rb = hostport.find("]")
        host = hostport[1:rb]
        port = hostport[rb + 1 :].lstrip(":") or "443"
    else:
        colon = hostport.rfind(":")
        if colon == -1:
            host, port = hostport, "443"
        else:
            host, port = hostport[:colon], hostport[colon + 1 :]
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


def read_vless(env):
    """The runtime key must already be a raw vless:// link (the -fetch oneshot
    guarantees this -- see vless-fetch.sh). No network, no decoding here."""
    secret_file = os.path.join(
        env.get("CREDENTIALS_DIRECTORY", "/run/credentials/sing-box.service"),
        env.get("SING_BOX_VLESS_CREDENTIAL", "vless-key"),
    )
    with open(secret_file, encoding="utf-8") as fh:
        raw = fh.read().strip()
    if not raw.startswith("vless://"):
        unit = "sing-box-" + env.get("SING_BOX_VLESS_CREDENTIAL", "vless-key").removesuffix("-key") + "-fetch"
        raise SystemExit(
            "credential is not a vless:// link; the -fetch oneshot failed or the "
            f"agenix secret holds an un-fetched https:// URL - run systemctl start {unit} first"
        )
    return raw


def build_outbound(vless, transport_override=""):
    uuid, host, port, params = parse_vless(vless)

    # transport + security from the link's own params; an override pin wins.
    stype = (transport_override or q(params, "type", "tcp")).lower()
    security = q(params, "security", "")
    if transport_override == "ws":
        stype = "ws"
    elif transport_override == "reality":
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


def build(env):
    outbound = build_outbound(read_vless(env), env.get("SING_BOX_VLESS_TRANSPORT_OVERRIDE", ""))
    return {"outbound": outbound, "dns": None, "default_domain_resolver": None}
