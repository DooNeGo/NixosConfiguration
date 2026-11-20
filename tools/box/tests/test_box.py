import tempfile
import unittest
from pathlib import Path

from boxlib import flake
from boxlib.fixtures import Check, Fixture, Ref, closure, parse_refs, plan
from boxlib.instance import CDI_DEVICE, cdi_has_gpu, gpu_args
from boxlib.layers import discover
from boxlib.runner import report, run_checks
from boxlib.targets import Target, UsageError, instance_name, parse_target


def fx(name, *requires):
    return Fixture(name, Path("setup"), Path("teardown"), tuple(requires))


def chk(name, *refs):
    return Check(name, Path(name + ".sh"), tuple(refs))


class TargetTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self.tmp.name)
        for d in ("system-config/nixos", "home-config/mathew", "elsewhere/x"):
            (self.repo / d).mkdir(parents=True)
            (self.repo / d / "flake.nix").write_text("{}")

    def tearDown(self):
        self.tmp.cleanup()

    def test_short_names(self):
        self.assertEqual(parse_target("system", "nixos", self.repo), Target("system", "system-config/nixos", "nixos"))
        self.assertEqual(parse_target("home", "mathew", self.repo).output, "homeConfigurations.mathew")

    def test_full_form(self):
        target = parse_target("system", "elsewhere/x#other", self.repo, cwd=self.repo)
        self.assertEqual((target.dir, target.attr), ("elsewhere/x", "other"))

    def test_rejects(self):
        for kind, text in [
            ("system", "missing"),
            ("system", "elsewhere/x"),
            ("system", "/etc#x"),
            ("home", "a b"),
            ("system", "elsewhere/x#1abc"),
        ]:
            with self.assertRaises(UsageError, msg=text):
                parse_target(kind, text, self.repo, cwd=self.repo)

    def test_instance_name(self):
        system = Target("system", "system-config/nixos", "nixos")
        home = Target("home", "home-config/mathew", "mathew")
        self.assertEqual(instance_name(system, home), "nixos-mathew")
        self.assertEqual(instance_name(system, None), "nixos")
        self.assertEqual(instance_name(system, home, "second"), "second")
        with self.assertRaises(UsageError):
            instance_name(system, home, "bad name")


class FixtureTests(unittest.TestCase):
    def test_parse_refs(self):
        text = "# requires: a (shared), b\n# requires: c\necho hi\n"
        self.assertEqual(parse_refs(text), (Ref("a", True), Ref("b", False), Ref("c", False)))
        with self.assertRaises(UsageError):
            parse_refs("# requires: a (loud)\n")
        self.assertEqual(parse_refs("# requires:\nexit 0\n"), (), "an empty header does not read the next line")

    def test_closure_puts_dependencies_first(self):
        fixtures = {f.name: f for f in (fx("session"), fx("ready", "session"))}
        self.assertEqual(closure(["ready"], fixtures), ["session", "ready"])
        with self.assertRaises(UsageError):
            closure(["nope"], fixtures)

    def test_cycle_is_a_usage_error(self):
        fixtures = {f.name: f for f in (fx("a", "b"), fx("b", "a"))}
        with self.assertRaises(UsageError):
            closure(["a"], fixtures)

    def test_plan_shares_and_isolates(self):
        fixtures = {f.name: f for f in (fx("session"), fx("ready", "session"))}
        checks = [
            chk("fresh", Ref("ready", False)),
            chk("plain"),
            chk("shared-a", Ref("ready", True)),
            chk("shared-b", Ref("ready", True)),
        ]
        steps = [(kind, item.name) for kind, item in plan(checks, fixtures)]
        self.assertEqual(
            steps,
            [
                ("check", "plain"),
                ("setup", "session"),
                ("setup", "ready"),
                ("check", "shared-a"),
                ("check", "shared-b"),
                ("teardown", "ready"),
                ("teardown", "session"),
                ("setup", "session"),
                ("setup", "ready"),
                ("check", "fresh"),
                ("teardown", "ready"),
                ("teardown", "session"),
            ],
        )


class FakeInstance:
    """run_script answers by the text of the script: `fail` in it means a non-zero status."""

    def __init__(self):
        self.ran = []

    def run_script(self, text, layers):
        self.ran.append(text)

        class Done:
            returncode = 1 if "fail" in text else 0
            stdout = "out of " + text

        return Done()


class RunnerTests(unittest.TestCase):
    def write(self, tmp, name, text):
        path = Path(tmp) / name
        path.write_text(text)
        return path

    def test_failing_check_and_failing_setup(self):
        with tempfile.TemporaryDirectory() as tmp:
            good = Check("good", self.write(tmp, "good.sh", "ok"), (Ref("f", False),))
            bad = Check("bad", self.write(tmp, "bad.sh", "fail"), ())
            fixtures = {"f": Fixture("f", self.write(tmp, "s", "setup fail"), self.write(tmp, "t", "teardown"), ())}
            inst = FakeInstance()
            results = {r.name: r for r in run_checks(inst, [], [good, bad], fixtures)}
            self.assertFalse(results["bad"].ok)
            self.assertFalse(results["good"].ok)
            self.assertIn("fixture f failed", results["good"].output)
            self.assertIn("teardown", inst.ran, "a failed setup is still torn down")
            self.assertNotIn("ok", inst.ran, "a check does not run on a broken fixture")

    def test_dependent_setup_is_skipped_when_its_requirement_failed(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Fixture("base", self.write(tmp, "bs", "setup fail"), self.write(tmp, "bt", "teardown-base"), ())
            top = Fixture("top", self.write(tmp, "ts", "setup-top"), self.write(tmp, "tt", "teardown-top"), ("base",))
            check = Check("c", self.write(tmp, "c.sh", "check"), (Ref("top", False),))
            inst = FakeInstance()
            results = run_checks(inst, [], [check], {"base": base, "top": top})
            self.assertFalse(results[0].ok)
            self.assertNotIn("setup-top", inst.ran)
            self.assertNotIn("teardown-top", inst.ran, "a setup that did not run is not torn down")
            self.assertIn("teardown-base", inst.ran)

    def test_failed_teardown_blocks_later_checks_of_that_fixture(self):
        with tempfile.TemporaryDirectory() as tmp:
            fixture = Fixture("f", self.write(tmp, "s", "setup-f"), self.write(tmp, "t", "teardown fail"), ())
            shared = Check("shared", self.write(tmp, "a.sh", "check-a"), (Ref("f", True),))
            fresh = Check("fresh", self.write(tmp, "b.sh", "check-b"), (Ref("f", False),))
            inst = FakeInstance()
            results = {r.name: r for r in run_checks(inst, [], [shared, fresh], {"f": fixture})}
            self.assertTrue(results["shared"].ok)
            self.assertFalse(results["teardown f"].ok)
            self.assertFalse(results["fresh"].ok)
            self.assertIn("earlier teardown failed", results["fresh"].output)
            self.assertEqual(inst.ran.count("setup-f"), 1, "the fixture is not set up again")
            self.assertNotIn("check-b", inst.ran)

    def test_no_results_is_not_a_pass(self):
        self.assertFalse(report([]))


class LayerAndFlakeTests(unittest.TestCase):
    def test_layers_and_render(self):
        with tempfile.TemporaryDirectory() as tmp:
            box = Path(tmp)
            (box / "container.nix").write_text("{}")
            (box / "systems/nixos").mkdir(parents=True)
            (box / "systems/nixos/module.nix").write_text("{}")
            (box / "systems/nixos/gpu").write_text("")
            (box / "homes/mathew").mkdir(parents=True)
            system = Target("system", "system-config/nixos", "nixos")
            home = Target("home", "home-config/mathew", "mathew")
            layers = discover(box, system, home)
            self.assertEqual([layer.name for layer in layers], ["container", "systems/nixos", "homes/mathew"])
            self.assertEqual([layer.gpu for layer in layers], [False, True, False])
            text = flake.render(Path("/repo"), box, system, home, layers, ["system-0.nix"], [])
            self.assertIn('"${box}/container.nix" "${box}/systems/nixos/module.nix" ./system-0.nix', text)
            self.assertIn("sys.nixosConfigurations.nixos", text)
            self.assertIn("home.homeConfigurations.mathew", text)
            self.assertIn('home.url = "git+file:///repo?dir=home-config/mathew"', text)


class GpuTests(unittest.TestCase):
    def test_gpu_args(self):
        self.assertEqual(gpu_args(False), [])
        # the group stays: the CDI spec alone leaves /dev/dri/card0 closed to the container root
        self.assertEqual(gpu_args(True), ["--device", CDI_DEVICE, "--group-add", "keep-groups"])

    def test_cdi_spec_lookup(self):
        with tempfile.TemporaryDirectory() as tmp:
            etc, run = Path(tmp) / "etc", Path(tmp) / "run"
            etc.mkdir()
            self.assertFalse(cdi_has_gpu((str(etc), str(run))))  # a missing directory is no spec
            (etc / "broken.json").write_text("{")
            (etc / "other.json").write_text('{"kind": "vendor.com/gpu", "devices": [{"name": "all"}]}')
            (etc / "single.json").write_text('{"kind": "nvidia.com/gpu", "devices": [{"name": "0"}]}')
            self.assertFalse(cdi_has_gpu((str(etc), str(run))))
            run.mkdir()
            (run / "nvidia.json").write_text('{"kind": "nvidia.com/gpu", "devices": [{"name": "0"}, {"name": "all"}]}')
            self.assertTrue(cdi_has_gpu((str(etc), str(run))))


if __name__ == "__main__":
    unittest.main()
