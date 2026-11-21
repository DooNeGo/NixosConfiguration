"""Fixtures and checks of the layers, and the order in which the runner sets them up and tears them down."""

import re
from dataclasses import dataclass
from graphlib import CycleError, TopologicalSorter
from pathlib import Path

from .layers import BACKENDS, Layer
from .targets import UsageError

_REQUIRES_RE = re.compile(r"^#[ \t]*requires:[ \t]*(.*)$", re.MULTILINE)
_BACKENDS_RE = re.compile(r"^#[ \t]*backends:[ \t]*(.*)$", re.MULTILINE)
_REF_RE = re.compile(r"([A-Za-z0-9][A-Za-z0-9_-]*)(?:\s*\((shared)\))?")


@dataclass(frozen=True)
class Ref:
    name: str
    shared: bool


@dataclass(frozen=True)
class Fixture:
    name: str
    setup: Path
    teardown: Path
    requires: tuple[str, ...]


@dataclass(frozen=True)
class Check:
    name: str
    path: Path
    refs: tuple[Ref, ...]


def parse_refs(text: str) -> tuple[Ref, ...]:
    """The `# requires: a (shared), b` lines of a check."""
    refs = []
    for line in _REQUIRES_RE.findall(text):
        for item in line.split(","):
            item = item.strip()
            if not item:
                continue
            match = _REF_RE.fullmatch(item)
            if not match:
                raise UsageError(f"invalid fixture reference {item!r}")
            refs.append(Ref(match.group(1), match.group(2) is not None))
    return tuple(refs)


def parse_backends(text: str) -> tuple[str, ...] | None:
    """The `# backends: container, vm` line of a check; without one the check runs on every backend."""
    found = _BACKENDS_RE.findall(text)
    if not found:
        return None
    names = tuple(item.strip() for line in found for item in line.replace(",", " ").split())
    unknown = [n for n in names if n not in BACKENDS]
    if not names or unknown:
        raise UsageError(f"invalid backends line {found[0]!r} (have: {', '.join(BACKENDS)})")
    return names


def discover_fixtures(layers: list[Layer]) -> dict[str, Fixture]:
    found: dict[str, Fixture] = {}
    for layer in layers:
        if not layer.fixtures_dir.is_dir():
            continue
        for root in sorted(p for p in layer.fixtures_dir.iterdir() if p.is_dir()):
            setup, teardown = root / "setup", root / "teardown"
            if not setup.is_file() or not teardown.is_file():
                raise UsageError(f"fixture {layer.name}/{root.name} needs setup and teardown")
            requires_file = root / "requires"
            requires = tuple(requires_file.read_text().split()) if requires_file.is_file() else ()
            if root.name in found:
                raise UsageError(f"fixture {root.name} is defined twice")
            found[root.name] = Fixture(root.name, setup, teardown, requires)
    return found


def discover_checks(layers: list[Layer], backend: str) -> list[Check]:
    """The checks of the layers that run on `backend`."""
    checks: list[Check] = []
    for layer in layers:
        if layer.checks_dir.is_dir():
            for path in sorted(layer.checks_dir.glob("*.sh")):
                if any(c.name == path.stem for c in checks):
                    raise UsageError(f"check {path.stem} is defined twice")
                text = path.read_text()
                backends = parse_backends(text)
                if backends is None or backend in backends:
                    checks.append(Check(path.stem, path, parse_refs(text)))
    return checks


def closure(names: list[str], fixtures: dict[str, Fixture]) -> list[str]:
    """The fixtures `names` need, dependencies first."""
    graph: dict[str, set[str]] = {}
    todo = list(names)
    while todo:
        name = todo.pop()
        if name in graph:
            continue
        if name not in fixtures:
            raise UsageError(f"unknown fixture {name!r}")
        graph[name] = set(fixtures[name].requires)
        todo.extend(fixtures[name].requires)
    try:
        return list(TopologicalSorter(graph).static_order())
    except CycleError:
        raise UsageError(f"the fixtures {', '.join(sorted(graph))} require each other in a cycle") from None


Step = tuple[str, "Fixture | Check"]


def plan(checks: list[Check], fixtures: dict[str, Fixture]) -> list[Step]:
    """Steps ("setup", fixture), ("check", check) and ("teardown", fixture).

    Checks without fixtures run first. A check whose references are all `(shared)` keeps its fixtures up for the
    next shared checks; every other check gets its fixtures set up fresh and torn down right after it.
    """
    plain = [c for c in checks if not c.refs]
    shared = [c for c in checks if c.refs and all(r.shared for r in c.refs)]
    fresh = [c for c in checks if c.refs and not all(r.shared for r in c.refs)]
    steps: list[Step] = [("check", c) for c in plain]
    active: list[str] = []
    for check in shared:
        for name in closure([r.name for r in check.refs], fixtures):
            if name not in active:
                active.append(name)
                steps.append(("setup", fixtures[name]))
        steps.append(("check", check))
    steps += [("teardown", fixtures[name]) for name in reversed(active)]
    for check in fresh:
        order = closure([r.name for r in check.refs], fixtures)
        steps += [("setup", fixtures[name]) for name in order]
        steps.append(("check", check))
        steps += [("teardown", fixtures[name]) for name in reversed(order)]
    return steps
