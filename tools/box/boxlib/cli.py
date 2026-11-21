"""Command line of box."""

import argparse
import fnmatch
import shlex
import shutil
import sys
from dataclasses import dataclass
from pathlib import Path

from . import flake as flake_mod
from .backends import make_instance, open_instance
from .fixtures import Check, Fixture, discover_checks, discover_fixtures, plan
from .instance import BoxError, Host, Instance, note, sh
from .layers import BACKENDS, Layer, discover
from .runner import report, run_checks
from .targets import NAME_RE, Target, UsageError, instance_name, parse_target

BOX_DIR = Path(__file__).resolve().parent.parent
REPO = BOX_DIR.parent.parent


class Parser(argparse.ArgumentParser):
    def error(self, message: str):
        print(f"box: {message}", file=sys.stderr)
        print("Try 'box --help' for more information.", file=sys.stderr)
        sys.exit(2)


def add_targets(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--system",
        required=True,
        metavar="TARGET",
        help="a NixOS configuration: NAME for system-config/NAME#NAME, or PATH#ATTR",
    )
    parser.add_argument(
        "--home",
        metavar="TARGET",
        help="a Home Manager configuration, written like --system",
    )
    parser.add_argument(
        "--system-module", action="append", default=[], metavar="FILE", help="an extra NixOS module for the system"
    )
    parser.add_argument(
        "--home-module", action="append", default=[], metavar="FILE", help="an extra Home Manager module"
    )
    parser.add_argument("--name", help="instance name (default: the system and the home names joined by -)")
    parser.add_argument(
        "--backend",
        choices=BACKENDS,
        default="container",
        help="container (default): the host GPU, fast. vm: a full boot with a kernel, a real login and a virtual GPU",
    )


def build_parser() -> argparse.ArgumentParser:
    parser = Parser(
        prog="box",
        description="Run a system and home configuration of this repository in a NixOS container "
        "(rootless podman) or a VM (QEMU), no sudo, on the host nix store, and test it.",
    )
    sub = parser.add_subparsers(dest="command", required=True, parser_class=Parser)
    for name, text in (
        ("build", "build the system and the home of an instance, nothing else"),
        ("up", "build and (re)create an instance, activate the home"),
        ("test", "up, run the checks of the layers, tear down"),
    ):
        p = sub.add_parser(name, help=text, description=text)
        add_targets(p)
        if name == "test":
            p.add_argument(
                "--tests",
                nargs="+",
                metavar="CHECK",
                help="run only these checks: names or shell patterns (session-*), separated by spaces or commas",
            )
            p.add_argument("--keep", action="store_true", help="leave the instance running")
    for name, text in (
        ("down", "stop an instance and remove its rootfs"),
        ("status", "state of an instance"),
        ("list", "running instances"),
    ):
        p = sub.add_parser(name, help=text, description=text)
        if name != "list":
            p.add_argument("--name")
    p = sub.add_parser("fixture", help="run the setup and/or teardown of a fixture of the layers")
    p.add_argument("fixture")
    p.add_argument("action", nargs="?", default="restart", choices=["setup", "teardown", "restart"])
    p.add_argument("--name")
    p = sub.add_parser("exec", help="run a command in the system as its root, after the lib.sh helpers of the layers")
    p.add_argument("--name")
    p.add_argument("cmd", nargs=argparse.REMAINDER, help="one argument is a shell command line")
    return parser


def targets_from(args) -> tuple[Target, Target | None]:
    system = parse_target("system", args.system, REPO)
    home = parse_target("home", args.home, REPO) if args.home else None
    if args.home_module and not home:
        raise UsageError("--home-module needs --home")
    return system, home


@dataclass
class Prepared:
    inst: Instance
    system: Target
    home: Target | None
    layers: list[Layer]
    flake_dir: Path


def read_extras(paths: list[str], prefix: str, flake_dir: Path) -> list[str]:
    names = []
    for i, text in enumerate(paths):
        source = Path(text)
        if not source.is_file():
            raise UsageError(f"no such module file {text!r}")
        name = f"{prefix}-{i}.nix"
        shutil.copyfile(source, flake_dir / name)
        names.append(name)
    return names


def instance_of(host: Host, args) -> tuple[Instance, Target, Target | None]:
    system, home = targets_from(args)
    return make_instance(host, instance_name(system, home, args.name), args.backend), system, home


def require_tracked() -> None:
    """The generated flake reads tools/box from git: an untracked layer file would be seen here and missing there."""
    untracked = sh(
        ["git", "-C", str(REPO), "ls-files", "--others", "--exclude-standard", "--", "tools/box"],
        capture=True,
        stdout_only=True,
    ).stdout.split()
    if untracked:
        raise UsageError(f"untracked files in tools/box (run 'git add -N' on them): {', '.join(untracked)}")


def prepare(inst: Instance, system: Target, home: Target | None, args) -> Prepared:
    """Writes the generated flake of an instance (the caller holds its lock)."""
    require_tracked()
    layers = discover(BOX_DIR, system, home, inst.backend)
    flake_dir = inst.dir / "flake"
    shutil.rmtree(flake_dir, ignore_errors=True)
    flake_dir.mkdir(parents=True)
    system_extras = read_extras(args.system_module, "system", flake_dir)
    home_extras = read_extras(args.home_module, "home", flake_dir)
    (flake_dir / "flake.nix").write_text(
        flake_mod.render(
            REPO, BOX_DIR, system, home, layers, system_extras, home_extras, inst.backend, inst.dir / "out"
        )
    )
    return Prepared(inst, system, home, layers, flake_dir)


def bring_up(host: Host, args, cleanup: bool):
    """Returns the instance, its layers and the lock. With `cleanup` a failure removes the half-made instance."""
    inst, system, home = instance_of(host, args)
    lock = inst.take_lock()
    prep = prepare(inst, system, home, args)
    note("layers: " + ", ".join(layer.name for layer in prep.layers))
    gpu = any(layer.gpu for layer in prep.layers)
    inst.check_host(gpu)
    inst.configure(prep.flake_dir, home is not None)
    top, home_out = inst.build(prep.flake_dir, home is not None)
    try:
        if inst.meta_file.is_file():
            previous = open_instance(host, inst.name)
            if previous.backend != inst.backend:
                previous.down()  # the unit name is the same in both backends
        inst.save_meta({"system": system.__dict__, "home": home.__dict__ if home else None, "user": inst.user})
        inst.start(top, gpu)
        state = inst.wait_up()
        note(f"{inst.name} is up ({state})")
        if state == "degraded":
            inst.inner("systemctl --failed --no-legend", check=False)
        if home_out:
            inst.activate(home_out, prep.layers)
    except BaseException:
        # `up` leaves a half-made instance to be looked at; `test` always cleans up.
        if cleanup:
            inst.down()
        raise
    return inst, prep.layers, lock


def resolve(host: Host, name: str | None) -> Instance:
    if name:
        if not NAME_RE.match(name):
            raise UsageError(f"invalid --name {name!r}")
        return open_instance(host, name)
    running = host.running_names()
    if not running:
        raise BoxError("no running instance; start one with 'box up'")
    if len(running) > 1:
        raise BoxError(f"several instances run ({', '.join(running)}); pick one with --name")
    return open_instance(host, running[0])


def layers_of(inst: Instance) -> list[Layer]:
    meta = inst.load_meta()
    home = Target(**meta["home"]) if meta["home"] else None
    return discover(BOX_DIR, Target(**meta["system"]), home, inst.backend)


def split_names(values: list[str] | None) -> list[str] | None:
    """The names of `--tests`, which may be separated by spaces, commas or both."""
    return [name for value in values for name in value.split(",") if name] if values is not None else None


def select_checks(checks: list[Check], only: list[str]) -> list[Check]:
    """The checks whose name matches one of the names or shell patterns of `only`, in their own order."""
    if not only:
        raise UsageError("--tests names no check")
    for pattern in only:
        if not any(fnmatch.fnmatchcase(c.name, pattern) for c in checks):
            raise UsageError(f"no check {pattern!r} (have: {', '.join(sorted(c.name for c in checks))})")
    return [c for c in checks if any(fnmatch.fnmatchcase(c.name, p) for p in only)]


def planned_checks(layers: list[Layer], only: list[str] | None, backend: str) -> tuple[list[Check], dict[str, Fixture]]:
    """The checks to run and their fixtures; every error of the layers shows here, before anything is built."""
    fixtures = discover_fixtures(layers)
    checks = discover_checks(layers, backend)
    if only is not None:
        checks = select_checks(checks, only)
    if not checks:
        raise UsageError(f"no checks for the {backend} backend in the layers of this system and home")
    plan(checks, fixtures)
    return checks, fixtures


def run_fixture(inst: Instance, layers: list[Layer], name: str, action: str) -> None:
    fixtures = discover_fixtures(layers)
    if name not in fixtures:
        raise BoxError(f"no fixture {name!r} in the layers of {inst.name} (have: {', '.join(sorted(fixtures))})")
    parts = {"setup": ["setup"], "teardown": ["teardown"], "restart": ["teardown", "setup"]}[action]
    for part in parts:
        fixture = fixtures[name]
        done = inst.run_script((fixture.setup if part == "setup" else fixture.teardown).read_text(), layers)
        if done.stdout:
            print(done.stdout.strip())
        if done.returncode != 0:
            raise BoxError(f"fixture {name} {part} failed")


def cmd_test(host: Host, args) -> int:
    system, home = targets_from(args)
    planned = discover(BOX_DIR, system, home, args.backend)
    checks, fixtures = planned_checks(planned, split_names(args.tests), args.backend)
    inst, layers, lock = bring_up(host, args, cleanup=True)
    try:
        ok = report(run_checks(inst, layers, checks, fixtures))
    finally:
        if not args.keep:
            inst.down()
        lock.close()
    return 0 if ok else 1


def dispatch(host: Host, args) -> int:
    cmd = args.command
    if cmd == "build":
        inst, system, home = instance_of(host, args)
        with inst.take_lock():
            prep = prepare(inst, system, home, args)
            # Other out links than `up` uses: a running instance keeps the roots it started from.
            top, home_out = inst.build(prep.flake_dir, home is not None, prefix="build-")
        print("\n".join(str(p) for p in [top, home_out] if p))
    elif cmd == "up":
        _, _, lock = bring_up(host, args, cleanup=False)
        lock.close()
    elif cmd == "test":
        return cmd_test(host, args)
    elif cmd == "list":
        print("\n".join(host.running_names()))
    elif cmd == "down":
        inst = resolve(host, args.name)
        with inst.take_lock():
            inst.down()
    elif cmd == "status":
        inst = resolve(host, args.name)
        print(
            f"{inst.name} ({inst.backend}): "
            + (f"running, systemd {inst.system_state()}" if inst.running() else "not running")
        )
    elif cmd == "fixture":
        inst = resolve(host, args.name)
        inst.require_running()
        run_fixture(inst, layers_of(inst), args.fixture, args.action)
    elif cmd == "exec":
        inst = resolve(host, args.name)
        inst.require_running()
        words = args.cmd[1:] if args.cmd[:1] == ["--"] else args.cmd
        if not words:
            raise UsageError("exec needs a command")
        script = words[0] if len(words) == 1 else shlex.join(words)
        return inst.inner(inst.with_prelude(script, layers_of(inst), strict=False), stdin=True, check=False).returncode
    return 0


def main() -> int:
    args = build_parser().parse_args()
    try:
        return dispatch(Host.create(REPO), args)
    except UsageError as err:
        print(f"box: {err}", file=sys.stderr)
        print("Try 'box --help' for more information.", file=sys.stderr)
        return 2
    except BoxError as err:
        print(f"box: {err}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130
