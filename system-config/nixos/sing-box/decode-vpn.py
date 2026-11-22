#!/usr/bin/env python3
"""Decode an Amnezia vpn:// string read from stdin.

awg      print the AmneziaWG .conf text of the selected container
xray     print one vless:// link for the selected xray container (tcp + reality only)
inspect  print key paths and value types of the decoded data, never values

--passthrough: input that does not start with vpn:// is copied to stdout unchanged.

Exit codes: 0 ok, 1 bad data, 2 bad usage. Messages never repeat input values.
"""

import base64
import io
import json
import re
import struct
import sys
import urllib.parse
import zlib

PREFIX = "vpn://"
MAX_INPUT = 1 << 20
MAX_DECOMPRESSED = 1 << 20
MAX_DEPTH = 16
# inspect prints the value of these keys only: they name a protocol feature and hold no secret
PLAIN_KEYS = frozenset(
    {
        "container",
        "defaultContainer",
        "default_container",
        "protocol",
        "network",
        "security",
        "flow",
        "fingerprint",
        "encryption",
        "loglevel",
        "format_version",
        "transport_proto",
        "xray_transport",
        "xray_security",
        "xray_flow",
        "xray_fingerprint",
        "xhttp_mode",
    }
)
AWG_CONTAINERS = ("amnezia-awg", "amnezia-awg2")
XRAY_CONTAINERS = ("amnezia-xray",)
BASE64URL = re.compile(r"[A-Za-z0-9_-]*")
MODES = ("awg", "xray", "inspect")


class DataError(Exception):
    pass


def unpack(text):
    """vpn:// + base64url(4-byte big-endian length + zlib(JSON)), the Qt qCompress layout."""
    body = "".join(text.split())
    if not body.startswith(PREFIX):
        raise DataError("input does not start with vpn://")
    payload = body[len(PREFIX) :]
    if not BASE64URL.fullmatch(payload):
        raise DataError("payload is not base64url")
    try:
        raw = base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4))
    except ValueError:  # binascii.Error is a ValueError: a payload of 1 mod 4 characters
        raise DataError("payload is not base64url") from None
    if len(raw) <= 4:
        raise DataError("payload is too short")
    (declared,) = struct.unpack(">I", raw[:4])
    inflater = zlib.decompressobj()
    try:
        data = inflater.decompress(raw[4:], MAX_DECOMPRESSED + 1)
    except zlib.error:
        raise DataError("payload is not zlib data") from None
    if len(data) > MAX_DECOMPRESSED:
        raise DataError("decompressed payload is too large")
    if not inflater.eof or inflater.unused_data:
        raise DataError("zlib data is truncated or has trailing bytes")
    if declared != len(data):
        raise DataError("length header does not match the data")
    try:
        doc = json.loads(data)
    except (ValueError, RecursionError):
        raise DataError("payload is not JSON") from None
    if not isinstance(doc, dict):
        raise DataError("payload is not a JSON object")
    return doc


def pick_container(doc, types):
    """default_container when it has a wanted type, else the only container of a wanted type."""
    containers = doc.get("containers")
    if not isinstance(containers, list):
        raise DataError("no containers list")
    wanted = [c for c in containers if isinstance(c, dict) and c.get("container") in types]
    default = doc.get("defaultContainer", doc.get("default_container"))
    for container in wanted:
        if container.get("container") == default:
            return container
    if len(wanted) == 1:
        return wanted[0]
    if not wanted:
        raise DataError("no container of the wanted type")
    raise DataError("several containers of the wanted type and the default one is not among them")


def last_config(container, protocol):
    section = container.get(protocol)
    cfg = section.get("last_config") if isinstance(section, dict) else None
    if isinstance(cfg, str):  # the AmneziaWG containers keep it as a JSON string, xray as an object
        try:
            cfg = json.loads(cfg)
        except (ValueError, RecursionError):
            raise DataError("last_config is not JSON") from None
    if cfg is None:
        raise DataError("container has no last_config")
    if not isinstance(cfg, dict):
        raise DataError("last_config is not a JSON object")
    return cfg


def conf_keys(text):
    """Key names of an INI-like .conf as 'Section.Key', without values."""
    section = ""
    keys = []
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("["):
            section = line.strip("[]")
        elif "=" in line and not line.startswith("#"):
            keys.append(f"{section}.{line.split('=', 1)[0].strip()}")
    return keys


def decode_awg(doc):
    conf = last_config(pick_container(doc, AWG_CONTAINERS), "awg").get("config")
    if not isinstance(conf, str) or not conf.strip():
        raise DataError("last_config has no config text")
    for line in conf.splitlines():
        key, _, value = line.partition("=")
        if key.strip().lower() == "privatekey" and value.strip().startswith("$"):
            raise DataError("PrivateKey is an unreplaced template placeholder")
    return conf.rstrip("\n") + "\n"


def field(obj, key, kind):
    value = obj.get(key) if isinstance(obj, dict) else None
    if not isinstance(value, kind) or isinstance(value, bool):
        raise DataError(f"xray config has no usable {key}")
    return value


def optional(obj, key, kind):
    value = obj.get(key)
    if value is None:
        return kind()
    if not isinstance(value, kind) or isinstance(value, bool):
        raise DataError(f"xray config has an unusable {key}")
    return value


def first(obj, key):
    items = field(obj, key, list)
    if not items or not isinstance(items[0], dict):
        raise DataError(f"xray config has no {key} entry")
    return items[0]


def ascii_text(value, name):
    if not value.isascii() or not value.strip():
        raise DataError(f"{name} is empty or not ASCII")
    return value


def decode_xray(doc):
    """One vless:// link in the form generate-config.py reads; whatever it would mistranslate is refused."""
    cfg = last_config(pick_container(doc, XRAY_CONTAINERS), "xray")
    outbound = first(cfg, "outbounds")
    if outbound.get("protocol") != "vless":
        raise DataError("xray outbound is not vless")
    vnext = first(outbound.get("settings"), "vnext")
    user = first(vnext, "users")
    host = ascii_text(field(vnext, "address", str), "address")
    port = field(vnext, "port", int)
    if not 0 < port < 65536:
        raise DataError("port is out of range")
    uuid = ascii_text(field(user, "id", str), "id")
    if user.get("encryption", "none") != "none":
        raise DataError("vless encryption is not supported")
    flow = user.get("flow", "")
    if flow not in ("", "xtls-rprx-vision"):
        raise DataError("flow is not supported")
    stream = field(outbound, "streamSettings", dict)
    if stream.get("network") not in ("tcp", "raw"):
        raise DataError("only the tcp transport is supported")
    if optional(optional(stream, "tcpSettings", dict), "header", dict).get("type", "none") != "none":
        raise DataError("tcp header obfuscation is not supported")
    if stream.get("security") != "reality":
        raise DataError("only security reality is supported")
    reality = field(stream, "realitySettings", dict)
    if optional(reality, "spiderX", str):
        print("decode-vpn: warning: spiderX is dropped", file=sys.stderr)
    query = {
        "type": "tcp",
        "security": "reality",
        "sni": ascii_text(optional(reality, "serverName", str) or host, "serverName"),
        "fp": optional(reality, "fingerprint", str) or "chrome",
        "pbk": ascii_text(field(reality, "publicKey", str), "publicKey"),
        "sid": optional(reality, "shortId", str),
        "flow": flow,
    }
    pairs = "&".join(f"{k}={urllib.parse.quote(v, safe='')}" for k, v in query.items() if v)
    netloc = f"[{host}]" if ":" in host else host
    return f"vless://{urllib.parse.quote(uuid, safe='')}@{netloc}:{port}?{pairs}\n"


def inspect(value, path="", depth=0):
    """Lines 'path: type'; JSON strings (last_config) and .conf text (config) are opened."""
    if depth > MAX_DEPTH:
        return [f"{path}: ..."]
    if isinstance(value, dict):
        lines = [f"{path}: object"] if path else []
        for key, item in value.items():
            lines += inspect(item, f"{path}.{key}" if path else key, depth + 1)
        return lines
    if isinstance(value, list):
        lines = [f"{path}: list[{len(value)}]"]
        for index, item in enumerate(value):
            lines += inspect(item, f"{path}[{index}]", depth + 1)
        return lines
    if isinstance(value, str):
        if path.endswith(".last_config"):
            try:
                return inspect(json.loads(value), path, depth + 1)
            except (ValueError, RecursionError):
                pass
        if path.endswith(".config") and "[Interface]" in value:
            return [f"{path}: conf keys {' '.join(conf_keys(value))}"]
        return [f"{path}: str = {value}" if path.rsplit(".", 1)[-1] in PLAIN_KEYS else f"{path}: str"]
    return [f"{path}: {type(value).__name__}"]


def run(mode, text):
    doc = unpack(text)
    if mode == "awg":
        return decode_awg(doc)
    if mode == "xray":
        return decode_xray(doc)
    return "\n".join(inspect(doc)) + "\n"


def main(argv):
    passthrough = argv[1:] == ["--passthrough"]
    if not argv or argv[0] not in MODES or (argv[1:] and not passthrough):
        print(f"usage: decode-vpn.py {{{'|'.join(MODES)}}} [--passthrough] < vpn-string", file=sys.stderr)
        return 2
    if passthrough:
        raw = sys.stdin.buffer.read()
        if not raw.lstrip().startswith(b"vpn://"):
            sys.stdout.buffer.write(raw)
            return 0
        sys.stdin = io.StringIO(raw.decode("utf-8", "replace"))
    text = sys.stdin.read(MAX_INPUT + 1)
    if len(text) > MAX_INPUT:
        print("decode-vpn: input is too large", file=sys.stderr)
        return 1
    try:
        sys.stdout.write(run(argv[0], text))
    except DataError as exc:
        print(f"decode-vpn: {exc}", file=sys.stderr)
        return 1
    except (AttributeError, KeyError, IndexError, TypeError):
        print("decode-vpn: unexpected data layout", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
