"""The system and home configurations a box instance is built from, and the instance name derived from them."""

import re
from dataclasses import dataclass
from pathlib import Path

NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]*$")
# A Nix attribute written without quotes does not start with a digit.
ATTR_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_-]*$")


class UsageError(Exception):
    """A wrong command line: exit status 2."""


@dataclass(frozen=True)
class Target:
    kind: str  # "system" or "home"
    dir: str  # flake directory, relative to the repository root
    attr: str  # name under nixosConfigurations or homeConfigurations

    @property
    def output(self) -> str:
        return ("nixosConfigurations" if self.kind == "system" else "homeConfigurations") + "." + self.attr


_SHORT_DIR = {"system": "system-config", "home": "home-config"}


def parse_target(kind: str, text: str, repo: Path, cwd: Path | None = None) -> Target:
    """`nixos` means system-config/nixos#nixos; a full form is PATH#ATTR with PATH inside the repository."""
    if "#" not in text and "/" not in text:
        target = Target(kind, f"{_SHORT_DIR[kind]}/{text}", text)
    else:
        path, sep, attr = text.partition("#")
        if not sep or not attr:
            raise UsageError(f"--{kind} {text!r}: a path needs #ATTR")
        resolved = (cwd or Path.cwd()).joinpath(path).resolve()
        try:
            rel = resolved.relative_to(repo.resolve())
        except ValueError:
            raise UsageError(f"--{kind} {text!r}: the flake must be inside {repo}") from None
        target = Target(kind, rel.as_posix(), attr)
    if not ATTR_RE.match(target.attr):
        raise UsageError(f"--{kind}: invalid attribute {target.attr!r}")
    if not (repo / target.dir / "flake.nix").is_file():
        raise UsageError(f"--{kind}: no flake in {target.dir}")
    return target


def instance_name(system: Target, home: Target | None, override: str | None = None) -> str:
    if override is not None:
        if not NAME_RE.match(override):
            raise UsageError(f"invalid --name {override!r}")
        return override
    return "-".join([system.attr, home.attr] if home else [system.attr])
