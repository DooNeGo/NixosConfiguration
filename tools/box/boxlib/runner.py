"""Runs the checks of the layers of an instance, with the fixtures they ask for."""

import re
import time
from dataclasses import dataclass

from .fixtures import Check, Fixture, closure, plan
from .instance import Instance
from .layers import Layer


@dataclass
class Result:
    name: str
    ok: bool
    seconds: float
    output: str


_CONTROL_RE = re.compile(r"\x1b\][^\x07]*\x07|[\x00-\x08\x0b-\x1f\x7f]")


def _run(inst: Instance, layers: list[Layer], path_text: str) -> tuple[bool, str]:
    done = inst.run_script(path_text, layers)
    return done.returncode == 0, _CONTROL_RE.sub("", done.stdout or "").strip()


def run_checks(inst: Instance, layers: list[Layer], checks: list[Check], fixtures: dict[str, Fixture]) -> list[Result]:
    needs = {c.name: set(closure([r.name for r in c.refs], fixtures)) for c in checks}
    failed: dict[str, str] = {}
    poisoned: set[str] = set()  # fixtures whose teardown failed: their state is unknown, so they are not set up again
    not_run: set[str] = set()  # setups skipped because a fixture they require failed; nothing to tear down
    results: list[Result] = []
    for kind, item in plan(checks, fixtures):
        started = time.monotonic()
        if kind == "setup":
            blockers = [name for name in item.requires if name in failed]
            if item.name in poisoned:
                failed[item.name] = "not run: its earlier teardown failed"
                not_run.add(item.name)
                continue
            if blockers:
                failed[item.name] = f"not run: {', '.join(blockers)} failed"
                not_run.add(item.name)
                continue
            ok, output = _run(inst, layers, item.setup.read_text())
            if not ok:
                failed[item.name] = output
        elif kind == "teardown":
            if item.name not in not_run:
                ok, output = _run(inst, layers, item.teardown.read_text())
                if not ok:
                    results.append(Result(f"teardown {item.name}", False, time.monotonic() - started, output))
                    poisoned.add(item.name)
            failed.pop(item.name, None)
            not_run.discard(item.name)
        else:
            broken = sorted(needs[item.name] & failed.keys())
            if broken:
                detail = "\n".join(f"fixture {name} failed:\n{failed[name]}" for name in broken)
                results.append(Result(item.name, False, 0.0, detail))
                continue
            ok, output = _run(inst, layers, item.path.read_text())
            results.append(Result(item.name, ok, time.monotonic() - started, output))
    return results


def report(results: list[Result]) -> bool:
    for result in results:
        print(f"{'ok  ' if result.ok else 'FAIL'} {result.name} ({result.seconds:.1f}s)")
        if not result.ok and result.output:
            print("\n".join("    " + line for line in result.output.splitlines()))
    passed = sum(r.ok for r in results)
    print(f"{passed}/{len(results)} passed")
    return bool(results) and passed == len(results)
