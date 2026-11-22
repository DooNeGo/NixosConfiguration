"""Tests for decode-vpn.py and its use in awg-prepare.sh and vless-fetch.sh, with synthetic data and fake keys."""

import base64
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import urllib.parse
import zlib
from pathlib import Path

from kinds import vless

HERE = Path(__file__).resolve().parent
DECODER = HERE / "decode-vpn.py"
PREPARE = HERE / "kinds" / "awg-prepare.sh"
RESOLVE = HERE / "kinds" / "vless-fetch.sh"
UUID = "11111111-2222-3333-4444-555555555555"
PBK = "cHVibGljLXJlYWxpdHkta2V5LTAwMDAwMDAwMDAwMDA"
SECRET = "c2VjcmV0LXByaXZhdGUta2V5LTAwMDAwMDAwMDAwMDAwMDAwMDA="

CONF = f"""[Interface]
PrivateKey = {SECRET}
Address = 10.8.1.2/32
DNS = 1.1.1.1, 1.0.0.1
Jc = 4
Jmin = 10
Jmax = 50
S1 = 100
S2 = 120
S3 = 20
S4 = 30
H1 = 1111-1200
H2 = 2222
I1 = <b 0xdeadbeef><r 16>

[Peer]
PublicKey = cHVibGljLWtleS0wMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDA=
PresharedKey = cHJlc2hhcmVkLTAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDA=
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = 198.51.100.1:51820
PersistentKeepalive = 25
"""


def qcompress(data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + zlib.compress(data)


def encode(raw: bytes) -> str:
    return "vpn://" + base64.urlsafe_b64encode(raw).decode().rstrip("=")


def awg_container(conf=CONF, name="amnezia-awg"):
    return {"container": name, "awg": {"last_config": json.dumps({"config": conf, "Jc": "4"})}}


def make_vpn(containers, default=None):
    doc = {"containers": containers}
    if default:
        doc["defaultContainer"] = default
    return encode(qcompress(json.dumps(doc).encode()))


def run_decoder(args, text):
    command = [sys.executable, "-I", "-B", str(DECODER), *args]
    return subprocess.run(command, input=text, capture_output=True, text=True, check=False)


def decode(mode, text):
    return run_decoder([mode], text)


def xray_config(**changes):
    """An xray last_config as the Amnezia app writes it; `changes` maps dotted paths to new values."""
    cfg = {
        "outbounds": [
            {
                "protocol": "vless",
                "settings": {
                    "vnext": [
                        {
                            "address": "198.51.100.9",
                            "port": 443,
                            "users": [{"id": UUID, "encryption": "none", "flow": "xtls-rprx-vision"}],
                        }
                    ]
                },
                "streamSettings": {
                    "network": "tcp",
                    "security": "reality",
                    "realitySettings": {
                        "fingerprint": "chrome",
                        "publicKey": PBK,
                        "serverName": "cdn.example.test",
                        "shortId": "ab12",
                        "spiderX": "",
                    },
                },
            }
        ]
    }
    for dotted, value in changes.items():
        node = cfg
        *parents, last = dotted.split(".")
        for key in parents:
            node = node[int(key)] if key.isdigit() else node[key]
        node[int(last) if last.isdigit() else last] = value
    return cfg


def xray_vpn(cfg=None, **extra):
    container = {"container": "amnezia-xray", "xray": {"last_config": xray_config() if cfg is None else cfg}}
    return make_vpn([container, awg_container()], "amnezia-xray", **extra)


class DecodeAwgTest(unittest.TestCase):
    def test_round_trip(self):
        result = decode("awg", make_vpn([awg_container()], "amnezia-awg"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, CONF)

    def test_awg2_container_and_whitespace(self):
        text = "\n  " + make_vpn([awg_container(name="amnezia-awg2")]) + "  \n"
        result = decode("awg", text)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, CONF)

    def test_default_container_wins_over_other_awg(self):
        other = awg_container(conf=CONF.replace("10.8.1.2", "10.8.1.3"), name="amnezia-awg2")
        result = decode("awg", make_vpn([other, awg_container()], "amnezia-awg"))
        self.assertEqual(result.stdout, CONF)

    def test_only_awg_container_is_used_when_default_is_other(self):
        xray = {"container": "amnezia-xray", "xray": {"last_config": "{}"}}
        result = decode("awg", make_vpn([xray, awg_container()], "amnezia-xray"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, CONF)

    def test_last_config_as_object_and_camel_case_default(self):
        awg = {"container": "amnezia-awg", "awg": {"last_config": {"config": CONF}}}
        xray = {"container": "amnezia-xray", "xray": {"last_config": {}}}
        doc = {"containers": [xray, awg], "defaultContainer": "amnezia-awg"}
        result = decode("awg", encode(qcompress(json.dumps(doc).encode())))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, CONF)

    def test_ambiguous_containers_fail(self):
        containers = [awg_container(), awg_container(name="amnezia-awg2")]
        result = decode("awg", make_vpn(containers, "amnezia-xray"))
        self.assertEqual(result.returncode, 1)

    def test_no_awg_container_fails(self):
        xray = {"container": "amnezia-xray", "xray": {"last_config": "{}"}}
        self.assertEqual(decode("awg", make_vpn([xray])).returncode, 1)

    def test_data_errors(self):
        bad_header = "vpn://" + base64.urlsafe_b64encode(struct.pack(">I", 1) + zlib.compress(b"{}")).decode()
        bomb = encode(qcompress(b" " * ((1 << 20) + 1)))
        bad_type = {"container": "amnezia-awg", "awg": {"last_config": 5}}
        no_config = {"container": "amnezia-awg", "awg": {"last_config": json.dumps({"Jc": "4"})}}
        placeholder = awg_container(conf=CONF.replace(SECRET, "$WIREGUARD_CLIENT_PRIVATE_KEY"))
        cases = {
            "empty": "",
            "wrong prefix": "vless://abc",
            "not base64url": "vpn://a+b/c==",
            "too short": "vpn://AAAA",
            "length 1 mod 4": "vpn://AAAAA",
            "not zlib": encode(struct.pack(">I", 3) + b"abc"),
            "header mismatch": bad_header,
            "bomb": bomb,
            "not json": encode(qcompress(b"nope")),
            "not an object": encode(qcompress(b"[]")),
            "last_config of a wrong type": make_vpn([bad_type]),
            "no config text": make_vpn([no_config]),
            "placeholder private key": make_vpn([placeholder]),
        }
        for name, text in cases.items():
            with self.subTest(name):
                result = decode("awg", text)
                self.assertEqual(result.returncode, 1, result.stdout)
                self.assertTrue(result.stderr.startswith("decode-vpn: "))
                self.assertNotIn(SECRET, result.stderr + result.stdout)

    def test_usage_errors_exit_2(self):
        for args in ([], ["nope"], ["awg", "extra"]):
            with self.subTest(args):
                self.assertEqual(run_decoder(args, "").returncode, 2)


class DecodeXrayTest(unittest.TestCase):
    def link(self, cfg=None):
        result = decode("xray", xray_vpn(cfg))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.count("\n"), 1)
        return result.stdout.strip()

    def test_reality_vision_link(self):
        link = urllib.parse.urlsplit(self.link())
        self.assertEqual((link.scheme, link.username, link.hostname, link.port), ("vless", UUID, "198.51.100.9", 443))
        self.assertEqual(
            urllib.parse.parse_qs(link.query),
            {
                "type": ["tcp"],
                "security": ["reality"],
                "sni": ["cdn.example.test"],
                "fp": ["chrome"],
                "pbk": [PBK],
                "sid": ["ab12"],
                "flow": ["xtls-rprx-vision"],
            },
        )

    def test_raw_is_tcp_and_empty_values_are_left_out(self):
        cfg = xray_config(
            **{"outbounds.0.streamSettings.network": "raw", "outbounds.0.settings.vnext.0.users.0.flow": ""}
        )
        cfg["outbounds"][0]["streamSettings"]["realitySettings"]["shortId"] = ""
        query = urllib.parse.parse_qs(urllib.parse.urlsplit(self.link(cfg)).query)
        self.assertEqual(query["type"], ["tcp"])
        self.assertNotIn("flow", query)
        self.assertNotIn("sid", query)

    def test_ipv6_address_is_bracketed(self):
        link = self.link(xray_config(**{"outbounds.0.settings.vnext.0.address": "2001:db8::1"}))
        self.assertEqual(urllib.parse.urlsplit(link).hostname, "2001:db8::1")
        self.assertIn("@[2001:db8::1]:443?", link)

    def test_spiderx_is_dropped_with_a_warning_without_its_value(self):
        cfg = xray_config()
        cfg["outbounds"][0]["streamSettings"]["realitySettings"]["spiderX"] = "/secret-path"
        result = decode("xray", xray_vpn(cfg))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("spiderX is dropped", result.stderr)
        self.assertNotIn("secret-path", result.stdout + result.stderr)

    def test_refused_configs(self):
        base = "outbounds.0.streamSettings"
        user = "outbounds.0.settings.vnext.0.users.0"
        cases = {
            "xhttp": {f"{base}.network": "xhttp"},
            "mkcp": {f"{base}.network": "kcp"},
            "grpc": {f"{base}.network": "grpc"},
            "ws": {f"{base}.network": "ws"},
            "tls": {f"{base}.security": "tls"},
            "no security": {f"{base}.security": "none"},
            "tcp header": {f"{base}.tcpSettings": {"header": {"type": "http"}}},
            "encryption": {f"{user}.encryption": "mlkem768x25519plus.native.0rtt.xyz"},
            "udp flow": {f"{user}.flow": "xtls-rprx-vision-udp443"},
            "not vless": {"outbounds.0.protocol": "vmess"},
            "port": {"outbounds.0.settings.vnext.0.port": 70000},
            "string port": {"outbounds.0.settings.vnext.0.port": "443"},
            "non-ascii sni": {f"{base}.realitySettings.serverName": "пример.test"},
            "tcpSettings not an object": {f"{base}.tcpSettings": "none"},
            "header not an object": {f"{base}.tcpSettings": {"header": []}},
            "serverName not a string": {f"{base}.realitySettings.serverName": 5},
            "shortId not a string": {f"{base}.realitySettings.shortId": ["ab"]},
            "fingerprint not a string": {f"{base}.realitySettings.fingerprint": {}},
            "empty public key": {f"{base}.realitySettings.publicKey": ""},
        }
        for name, changes in cases.items():
            with self.subTest(name):
                result = decode("xray", xray_vpn(xray_config(**changes)))
                self.assertEqual(result.returncode, 1, result.stdout)
                self.assertTrue(result.stderr.startswith("decode-vpn: "))
                self.assertNotIn(PBK, result.stderr + result.stdout)

    def test_missing_pieces(self):
        for name, cfg in {"no outbounds": {}, "empty outbounds": {"outbounds": []}}.items():
            with self.subTest(name):
                self.assertEqual(decode("xray", xray_vpn(cfg)).returncode, 1)
        awg_only = make_vpn([awg_container()], "amnezia-awg")
        self.assertEqual(decode("xray", awg_only).returncode, 1)

    def test_generate_config_reads_the_link_as_intended(self):
        outbound = vless.build_outbound(self.link())
        self.assertEqual(
            (outbound["type"], outbound["server"], outbound["server_port"], outbound["uuid"]),
            ("vless", "198.51.100.9", 443, UUID),
        )
        self.assertEqual(outbound["flow"], "xtls-rprx-vision")
        self.assertEqual(outbound["tls"]["server_name"], "cdn.example.test")
        self.assertEqual(outbound["tls"]["utls"], {"enabled": True, "fingerprint": "chrome"})
        self.assertEqual(outbound["tls"]["reality"], {"enabled": True, "public_key": PBK, "short_id": "ab12"})
        self.assertNotIn("transport", outbound)


@unittest.skipUnless(shutil.which("bash"), "bash is needed")
class ResolveCredentialTest(unittest.TestCase):
    def run_resolve(self, text):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            (tmp / "credential").write_text(text)
            env = {
                **os.environ,
                "SING_BOX_VLESS_CREDENTIAL_FILE": str(tmp / "credential"),
                "SING_BOX_VLESS_KEY_FILE": str(tmp / "key"),
                "SING_BOX_DECODE_VPN": str(DECODER),
            }
            result = subprocess.run(["bash", str(RESOLVE)], env=env, capture_output=True, text=True, check=False)
            key = tmp / "key"
            return result, key.read_text() if key.exists() else None

    def test_vpn_string_becomes_the_runtime_key(self):
        result, key = self.run_resolve(xray_vpn() + "\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(key, decode("xray", xray_vpn()).stdout)
        self.assertNotIn(PBK, result.stdout + result.stderr)

    def test_leading_and_trailing_whitespace_is_ignored(self):
        result, key = self.run_resolve("\n   " + xray_vpn() + "  \n\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(key, decode("xray", xray_vpn()).stdout)

    def test_a_vless_link_still_passes_through(self):
        link = "vless://" + UUID + "@198.51.100.9:443?type=tcp&security=reality"
        result, key = self.run_resolve(link + "\n")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(key, link + "\n")

    def test_a_bad_vpn_string_leaves_no_key(self):
        result, key = self.run_resolve("vpn://AAAA\n")
        self.assertEqual(result.returncode, 1)
        self.assertIsNone(key)
        self.assertIn("cannot decode the vpn:// string", result.stderr)


class InspectTest(unittest.TestCase):
    def test_prints_plain_values_of_known_keys_only(self):
        stream = {
            "network": "tcp",
            "security": "reality",
            "realitySettings": {"publicKey": SECRET, "serverName": "x.test"},
        }
        config = {"outbounds": [{"protocol": "vless", "streamSettings": stream}]}
        xray = {"container": "amnezia-xray", "xray": {"last_config": config}}
        doc = {"containers": [xray], "defaultContainer": "amnezia-xray", "hostName": "198.51.100.7"}
        result = decode("inspect", encode(qcompress(json.dumps(doc).encode())))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("streamSettings.network: str = tcp", result.stdout)
        self.assertIn("streamSettings.security: str = reality", result.stdout)
        self.assertIn("outbounds[0].protocol: str = vless", result.stdout)
        for value in (SECRET, "x.test", "198.51.100.7"):
            self.assertNotIn(value, result.stdout)

    def test_prints_structure_without_values(self):
        result = decode("inspect", make_vpn([awg_container()], "amnezia-awg"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("containers[0].awg.last_config.config: conf keys", result.stdout)
        self.assertIn("Interface.S3", result.stdout)
        self.assertIn("Interface.I1", result.stdout)
        for value in (SECRET, "198.51.100.1", "deadbeef"):
            self.assertNotIn(value, result.stdout)


@unittest.skipUnless(shutil.which("bash") and shutil.which("awk"), "bash and awk are needed")
class PrepareAwgTest(unittest.TestCase):
    def run_prepare(self, source_text):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            (tmp / "source").write_text(source_text)
            env = {
                **os.environ,
                "SING_BOX_AWG_SOURCE_FILE": str(tmp / "source"),
                "SING_BOX_AWG_OUT_FILE": str(tmp / "out.conf"),
                "SING_BOX_AWG_ADDR_FILE": str(tmp / "address"),
                "SING_BOX_AWG_TABLE": "51820",
                "SING_BOX_DECODE_VPN": str(DECODER),
            }
            result = subprocess.run(["bash", str(PREPARE)], env=env, capture_output=True, text=True, check=False)
            if result.returncode != 0:
                return result, None, None
            return result, (tmp / "out.conf").read_text(), (tmp / "address").read_text()

    def test_vpn_string_and_plain_conf_give_the_same_output(self):
        plain = self.run_prepare(CONF)
        vpn = self.run_prepare(make_vpn([awg_container()], "amnezia-awg") + "\n")
        self.assertEqual(plain[0].returncode, 0, plain[0].stderr)
        self.assertEqual(vpn[0].returncode, 0, vpn[0].stderr)
        self.assertEqual(plain[1:], vpn[1:])
        self.assertIn("S3 = 20", vpn[1])
        self.assertNotIn("DNS", vpn[1])
        self.assertEqual(vpn[2], "10.8.1.2\n")

    def test_bad_vpn_string_fails_without_output(self):
        result, out, _ = self.run_prepare("vpn://AAAA\n")
        self.assertNotEqual(result.returncode, 0)
        self.assertIsNone(out)
        self.assertIn("cannot decode the vpn:// string", result.stderr)


if __name__ == "__main__":
    unittest.main()
