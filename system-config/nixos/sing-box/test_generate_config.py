"""Tests for generate-config.py: the kind registry and the shared part of config.json."""

import importlib.util
import json
import re
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent

spec = importlib.util.spec_from_file_location("generate_config", HERE / "generate-config.py")
generate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generate)

DOMAINS = ["a.test", "b.test"]
BASE = {"SING_BOX_PROXY_DOMAINS": json.dumps(DOMAINS), "SING_BOX_LISTEN_PORT": "2081", "SING_BOX_ROUTE_MATCH": "domain"}


class RegistryTest(unittest.TestCase):
    def test_python_kinds_match_nix_kinds(self):
        nix = {p.stem for p in (HERE / "kinds").glob("*.nix")}
        py = {p.stem for p in (HERE / "kinds").glob("*.py") if not p.stem.startswith(("test_", "__"))}
        self.assertEqual(set(generate.KINDS), nix)
        self.assertEqual(py, nix)
        nix_file = (HERE.parent / "sing-box.nix").read_text()
        listed = set(re.findall(r"^\s*(\w+) = \./sing-box/kinds/\w+\.nix;", nix_file, re.M))
        self.assertEqual(listed, nix)


class BuildConfigTest(unittest.TestCase):
    def test_awg(self):
        with tempfile.TemporaryDirectory() as tmp:
            addr = Path(tmp) / "address"
            addr.write_text("10.8.1.2\n")
            env = {
                **BASE,
                "SING_BOX_KIND": "awg",
                "SING_BOX_AWG_INTERFACE": "awg0",
                "SING_BOX_AWG_ADDR_FILE": str(addr),
            }
            config = generate.build_config(env, DOMAINS)
        self.assertEqual(config["outbounds"][0]["bind_interface"], "awg0")
        self.assertEqual(config["route"]["default_domain_resolver"], "dns-local")
        self.assertIn("dns", config)

    def test_vless(self):
        link = "vless://11111111-2222-3333-4444-555555555555@h.example.test:443?type=tcp&security=tls"
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "k").write_text(link)
            env = {**BASE, "SING_BOX_KIND": "vless", "CREDENTIALS_DIRECTORY": tmp, "SING_BOX_VLESS_CREDENTIAL": "k"}
            config = generate.build_config(env, DOMAINS)
        self.assertEqual(config["outbounds"][0]["type"], "vless")
        self.assertNotIn("dns", config)
        self.assertNotIn("default_domain_resolver", config["route"])

    def _tun_config(self, kind):
        tun = {
            "interface": "sbtun-x",
            "address": "172.19.0.5/30",
            "dnsAddress": "172.19.0.6",
            "fakeRange": "198.19.0.0/16",
        }
        env = {**BASE, "SING_BOX_KIND": kind, "SING_BOX_TUN": json.dumps(tun)}
        with tempfile.TemporaryDirectory() as tmp:
            if kind == "vless":
                link = "vless://11111111-2222-3333-4444-555555555555@h.example.test:443?type=tcp&security=tls"
                (Path(tmp) / "k").write_text(link)
                env.update({"CREDENTIALS_DIRECTORY": tmp, "SING_BOX_VLESS_CREDENTIAL": "k"})
            else:
                (Path(tmp) / "address").write_text("10.8.1.2\n")
                env.update({"SING_BOX_AWG_INTERFACE": "awg0", "SING_BOX_AWG_ADDR_FILE": str(Path(tmp) / "address")})
            return generate.build_config(env, DOMAINS)

    def test_tun_adds_fakeip_for_the_domains_only(self):
        config = self._tun_config("vless")
        tun = next(i for i in config["inbounds"] if i["type"] == "tun")
        self.assertFalse(tun["auto_route"])
        self.assertNotIn("stack", tun)
        self.assertEqual(tun["interface_name"], "sbtun-x")
        self.assertEqual(tun["address"], ["172.19.0.5/30"])
        self.assertEqual(tun["dns_address"], "172.19.0.6")
        fake = [s for s in config["dns"]["servers"] if s["type"] == "fakeip"]
        self.assertEqual(fake[0]["inet4_range"], "198.19.0.0/16")
        self.assertEqual(config["dns"]["rules"][0]["inbound"], ["tun-in"])
        self.assertEqual(config["dns"]["final"], "dns-local")
        self.assertEqual(config["route"]["default_domain_resolver"], "dns-local")
        self.assertEqual(config["route"]["rules"][1], {"protocol": "dns", "action": "hijack-dns"})
        self.assertEqual(config["route"]["final"], "direct")
        self.assertTrue(config["experimental"]["cache_file"]["store_fakeip"])

    def test_tun_keeps_the_resolvers_of_the_kind(self):
        config = self._tun_config("awg")
        tags = [s["tag"] for s in config["dns"]["servers"]]
        self.assertEqual(tags, ["dns-tunnel", "dns-local", "dns-fakeip"])
        self.assertEqual(config["route"]["default_domain_resolver"], "dns-local")

    def test_kind_is_required(self):
        with self.assertRaises(SystemExit):
            generate.build_config(BASE, DOMAINS)

    def test_shared_part(self):
        link = "vless://11111111-2222-3333-4444-555555555555@h.example.test:443?type=tcp&security=tls"
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "k").write_text(link)
            env = {**BASE, "SING_BOX_KIND": "vless", "CREDENTIALS_DIRECTORY": tmp, "SING_BOX_VLESS_CREDENTIAL": "k"}
            config = generate.build_config(env, DOMAINS)
        self.assertEqual(config["inbounds"][0]["listen_port"], 2081)
        self.assertEqual(config["route"]["rules"][1], {"domain": DOMAINS, "action": "route", "outbound": "proxy"})
        self.assertEqual(config["route"]["final"], "direct")

    def test_unknown_kind(self):
        with self.assertRaises(SystemExit):
            generate.build_config({**BASE, "SING_BOX_KIND": "bogus"}, DOMAINS)

    def test_domains_are_required(self):
        for raw in (None, "[]", "{}"):
            with self.subTest(raw=raw), self.assertRaises(SystemExit):
                generate.load_domains({} if raw is None else {"SING_BOX_PROXY_DOMAINS": raw})


if __name__ == "__main__":
    unittest.main()
