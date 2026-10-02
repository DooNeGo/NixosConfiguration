#!/usr/bin/env python3
"""Generate /run/sing-box/config.json for the system-level sing-box service.

The VLESS subscription secret lives OUTSIDE the Nix store, so it can never be
committed to the repository. This script is the only place that touches it.

Secret source: systemd credential "vless-key", exposed to executed commands as
  $CREDENTIALS_DIRECTORY/vless-key. systemd names that directory after the FULL
  unit name, i.e. /run/credentials/sing-box.service/ (backed by
  /etc/sing-box/vless-key, root-owned 0600, provisioned outside Nix).
  NOTE: /run/credentials/sing-box/ (without .service) never exists — systemd
  does not strip the unit suffix.
  * If it contains a raw `vless://...` link, that link is used directly.
  * Otherwise it is treated as a subscription URL: it is fetched, the response
    is base64-decoded (if needed) and the first `vless://` link is used.

The list of domains routed through the proxy is injected by the Nix module via
the SING_BOX_PROXY_DOMAINS environment variable (a JSON array).
"""

import base64
import json
import os
import urllib.parse
import urllib.request

SECRET_FILE = os.path.join(
    os.environ.get("CREDENTIALS_DIRECTORY", "/run/credentials/sing-box.service"),
    "vless-key",
)
OUT_FILE = "/run/sing-box/config.json"
LISTEN_ADDRESS = "127.0.0.1"
LISTEN_PORT = 2080


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


def extract_vless(raw):
    if raw.startswith("vless://"):
        return raw
    req = urllib.request.Request(raw, headers={"User-Agent": "v2rayNG/1.8.5"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        body = resp.read().decode("utf-8", "replace").strip()
    try:
        decoded = base64.b64decode(body + "=" * (-len(body) % 4)).decode(
            "utf-8", "replace"
        )
    except Exception:
        decoded = body
    for line in decoded.splitlines():
        line = line.strip()
        if line.startswith("vless://"):
            return line
    raise SystemExit("no vless:// link found in subscription response")


def build_outbound(vless):
    url = urllib.parse.urlparse(vless)
    query = urllib.parse.parse_qs(url.query)

    def q(name, default=None):
        vals = query.get(name)
        return vals[0] if vals else default

    outbound = {
        "type": "vless",
        "tag": "proxy",
        "server": url.hostname,
        "server_port": int(url.port or 443),
        "uuid": urllib.parse.unquote(url.username or ""),
        "tls": {
            "enabled": True,
            "server_name": q("sni", url.hostname),
            "utls": {"enabled": True, "fingerprint": q("fp", "chrome")},
            "reality": {
                "enabled": True,
                "public_key": q("pbk", ""),
                "short_id": q("sid", ""),
            },
        },
    }
    flow = q("flow")
    if flow:
        outbound["flow"] = flow
    return outbound


def build_config(domains):
    vless = extract_vless(read_secret())
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
                {"domain_suffix": domains, "action": "route", "outbound": "proxy"},
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
