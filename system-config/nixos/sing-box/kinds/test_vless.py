"""Tests for kinds/vless.py with a fake link."""

import tempfile
import unittest
from pathlib import Path

from kinds import vless

UUID = "11111111-2222-3333-4444-555555555555"
REALITY = (
    f"vless://{UUID}@Example.test:8443?type=tcp&security=reality&sni=cdn.example.test"
    "&fp=firefox&pbk=KEY&sid=ab12&flow=xtls-rprx-vision#name"
)
WS = f"vless://{UUID}@h.example.test:443?type=ws&security=tls&path=%2Fws&host=x.test&ed=2048&flow=xtls-rprx-vision"


class ParseTest(unittest.TestCase):
    def test_fields(self):
        uuid, host, port, params = vless.parse_vless(REALITY)
        self.assertEqual((uuid, host, port), (UUID, "example.test", "8443"))
        self.assertEqual(vless.q(params, "sid"), "ab12")
        self.assertIsNone(vless.q(params, "missing"))

    def test_ipv6_and_default_port(self):
        _, host, port, _ = vless.parse_vless(f"vless://{UUID}@[2001:db8::1]")
        self.assertEqual((host, port), ("2001:db8::1", "443"))

    def test_missing_separator(self):
        with self.assertRaises(SystemExit):
            vless.parse_vless("vless://no-at-sign")


class OutboundTest(unittest.TestCase):
    def test_reality(self):
        out = vless.build_outbound(REALITY)
        self.assertEqual(out["server_port"], 8443)
        self.assertEqual(out["flow"], "xtls-rprx-vision")
        self.assertEqual(out["tls"]["utls"]["fingerprint"], "firefox")
        self.assertEqual(out["tls"]["reality"]["short_id"], "ab12")
        self.assertNotIn("transport", out)

    def test_ws_drops_flow(self):
        out = vless.build_outbound(WS)
        self.assertNotIn("flow", out)
        self.assertEqual(
            out["transport"], {"type": "ws", "path": "/ws", "headers": {"Host": "x.test"}, "max_early_data": 2048}
        )

    def test_override_pins_transport(self):
        self.assertEqual(vless.build_outbound(REALITY, "ws")["transport"]["type"], "ws")


class BuildTest(unittest.TestCase):
    def build(self, text):
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "k").write_text(text + "\n")
            return vless.build({"CREDENTIALS_DIRECTORY": tmp, "SING_BOX_CREDENTIAL": "k"})

    def test_result_shape(self):
        result = self.build(REALITY)
        self.assertEqual(result["outbound"]["tag"], "proxy")
        self.assertIsNone(result["dns"])
        self.assertIsNone(result["default_domain_resolver"])

    def test_unfetched_credential_is_refused(self):
        with self.assertRaises(SystemExit):
            self.build("https://sub.example.test/x")


if __name__ == "__main__":
    unittest.main()
