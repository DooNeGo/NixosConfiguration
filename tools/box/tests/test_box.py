import tempfile
import unittest
from pathlib import Path

from boxlib import flake
from boxlib.cli import select_checks, split_names
from boxlib.container import CDI_DEVICE, cdi_has_gpu, gpu_args
from boxlib.fixtures import Check, Fixture, Ref, closure, discover_checks, parse_backends, parse_refs, plan
from boxlib.layers import Layer, discover
from boxlib.runner import report, run_checks
from boxlib.targets import Target, UsageError, instance_name, parse_target
from boxlib.vm import guest_cid, qemu_options


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
    def make_box(self, tmp):
        box = Path(tmp)
        (box / "backends/container").mkdir(parents=True)
        (box / "backends/container/module.nix").write_text("{}")
        (box / "backends/vm").mkdir(parents=True)
        (box / "backends/vm/module.nix").write_text("{}")
        (box / "systems/nixos").mkdir(parents=True)
        (box / "systems/nixos/module.nix").write_text("{}")
        (box / "systems/nixos/vm.nix").write_text("{}")
        (box / "systems/nixos/gpu").write_text("")
        (box / "homes/mathew").mkdir(parents=True)
        (box / "homes/mathew/module.nix").write_text("{}")
        return box

    def test_layers_and_render(self):
        with tempfile.TemporaryDirectory() as tmp:
            box = self.make_box(tmp)
            system = Target("system", "system-config/nixos", "nixos")
            home = Target("home", "home-config/mathew", "mathew")
            layers = discover(box, system, home)
            names = ["backends", "backends/container", "systems/nixos", "homes/mathew"]
            self.assertEqual([layer.name for layer in layers], names)
            self.assertEqual([layer.gpu for layer in layers], [False, False, True, False])
            text = flake.render(Path("/repo"), box, system, home, layers, ["system-0.nix"], [])
            self.assertIn(
                '"${box}/backends/container/module.nix" "${box}/systems/nixos/module.nix" ./system-0.nix', text
            )
            self.assertNotIn("vm.nix", text, "a module of another backend is not applied")
            self.assertIn("toplevel = (box.lib.mkSystem", text)
            self.assertIn("sys.nixosConfigurations.nixos", text)
            self.assertIn("home.homeConfigurations.mathew", text)
            self.assertIn('modules = [ "${box}/homes/mathew/module.nix" ];', text)
            self.assertIn('home.url = "git+file:///repo?dir=home-config/mathew"', text)

    def test_vm_layers_and_render(self):
        with tempfile.TemporaryDirectory() as tmp:
            box = self.make_box(tmp)
            system = Target("system", "system-config/nixos", "nixos")
            home = Target("home", "home-config/mathew", "mathew")
            layers = discover(box, system, home, "vm")
            self.assertEqual(layers[1].name, "backends/vm")
            text = flake.render(Path("/repo"), box, system, home, layers, [], [], "vm", Path("/state/out"))
            self.assertIn('"${box}/systems/nixos/vm.nix"', text)
            self.assertNotIn("container.nix", text)
            self.assertIn("vm = (box.lib.mkSystem", text)
            self.assertIn("config.system.build.vm", text)
            self.assertIn('source = "/state/out"', text)
            self.assertIn("virtualisation.additionalPaths = [ homePackage ]", text)
            self.assertIn("lib.username", text)

    def test_vm_needs_out_dir(self):
        with tempfile.TemporaryDirectory() as tmp:
            box = self.make_box(tmp)
            system = Target("system", "system-config/nixos", "nixos")
            layers = discover(box, system, None, "vm")
            with self.assertRaises(ValueError):
                flake.render(Path("/repo"), box, system, None, layers, [], [], "vm")

    def test_unknown_backend(self):
        with self.assertRaises(UsageError):
            discover(Path("/box"), Target("system", "d", "a"), None, "kvm")


class BackendTests(unittest.TestCase):
    def test_parse_backends(self):
        self.assertIsNone(parse_backends("# requires: a\nexit 0\n"), "no line: every backend")
        self.assertEqual(parse_backends("# backends: vm\n"), ("vm",))
        self.assertEqual(parse_backends("# backends: container, vm\n"), ("container", "vm"))
        for text in ("# backends:\n", "# backends: kvm\n"):
            with self.assertRaises(UsageError, msg=text):
                parse_backends(text)

    def test_checks_of_a_backend(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "checks").mkdir()
            for name, text in (
                ("any", "exit 0\n"),
                ("only-vm", "# backends: vm\nexit 0\n"),
                ("both", "# backends: container vm\n"),
            ):
                (root / "checks" / f"{name}.sh").write_text(text)
            layer = Layer("systems/x", "system", root, ())
            self.assertEqual([c.name for c in discover_checks([layer], "container")], ["any", "both"])
            self.assertEqual([c.name for c in discover_checks([layer], "vm")], ["any", "both", "only-vm"])

    def test_split_names(self):
        self.assertIsNone(split_names(None))
        self.assertEqual(split_names(["a,b", "c*", ",d"]), ["a", "b", "c*", "d"])
        self.assertEqual(split_names([","]), [], "separators only: no name, an error later, not every check")

    def test_select_checks(self):
        checks = [Check(n, Path(f"{n}.sh"), ()) for n in ("session-order", "session-frame", "unlock-frame")]
        names = lambda only: [c.name for c in select_checks(checks, only)]  # noqa: E731
        self.assertEqual(names(["unlock-frame"]), ["unlock-frame"])
        self.assertEqual(names(["session-*"]), ["session-order", "session-frame"])
        self.assertEqual(names(["unlock-frame", "session-order"]), ["session-order", "unlock-frame"], "their own order")
        with self.assertRaises(UsageError):
            select_checks(checks, ["session-*", "missing"])
        with self.assertRaises(UsageError):
            select_checks(checks, [])

    def test_guest_cid_and_qemu_options(self):
        self.assertEqual(guest_cid("nixos-mathew"), guest_cid("nixos-mathew"))
        self.assertNotEqual(guest_cid("a"), guest_cid("b"))
        self.assertGreaterEqual(guest_cid("a"), 100, "0 to 2 are reserved")
        plain = qemu_options(7, Path("/c.log"), "KEY", None)
        self.assertEqual(plain[-2:], ["-display", "none"])
        self.assertIn("vhost-vsock-pci,guest-cid=7", plain)
        gpu = qemu_options(7, Path("/c.log"), "KEY", Path("/dev/dri/renderD128"))
        self.assertIn("virtio-vga-gl", gpu)
        self.assertIn("egl-headless,gl=on,rendernode=/dev/dri/renderD128", gpu)
        self.assertTrue(all(" " not in item for item in gpu), "QEMU_OPTS is split on spaces")


class GpuTests(unittest.TestCase):
    def test_gpu_args(self):
        self.assertEqual(gpu_args(False), [])
        # the group stays: the CDI spec alone leaves /dev/dri/card0 closed to the container user
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
