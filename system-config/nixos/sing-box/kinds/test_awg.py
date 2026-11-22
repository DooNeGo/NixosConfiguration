"""Tests for kinds/awg.py."""

import tempfile
import unittest
from pathlib import Path

from kinds import awg


class BuildTest(unittest.TestCase):
    def build(self, addr_text, **extra):
        with tempfile.TemporaryDirectory() as tmp:
            addr = Path(tmp) / "address"
            if addr_text is not None:
                addr.write_text(addr_text)
            env = {"SING_BOX_AWG_INTERFACE": "awg0", "SING_BOX_AWG_ADDR_FILE": str(addr), **extra}
            return awg.build(env)

    def test_binds_to_interface_and_address(self):
        result = self.build("10.8.1.2\n")
        out = result["outbound"]
        self.assertEqual((out["type"], out["tag"]), ("direct", "proxy"))
        self.assertEqual((out["bind_interface"], out["inet4_bind_address"]), ("awg0", "10.8.1.2"))
        self.assertEqual(result["default_domain_resolver"], "dns-local")
        self.assertEqual(result["dns"]["servers"][0]["server"], "1.1.1.1")

    def test_tunnel_dns_override(self):
        result = self.build("10.8.1.2", SING_BOX_AWG_TUNNEL_DNS="9.9.9.9")
        self.assertEqual(result["dns"]["servers"][0]["server"], "9.9.9.9")

    def test_refusals(self):
        for text in (None, "not-an-address", "10.8.1"):
            with self.subTest(text=text), self.assertRaises(SystemExit):
                self.build(text)
        with self.assertRaises(SystemExit):
            awg.build({})


if __name__ == "__main__":
    unittest.main()
