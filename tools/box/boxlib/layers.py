"""Layers: the directories of tools/box that hold the overrides, fixtures and checks of one target."""

from dataclasses import dataclass
from pathlib import Path

from .targets import Target, UsageError

# The output of the generated flake that holds the system of a backend: packages.<system>.<attr>, and the
# config.system.build.<attr> it comes from.
SYSTEM_ATTR = {"container": "toplevel", "vm": "vm"}
BACKENDS = tuple(SYSTEM_ATTR)


@dataclass(frozen=True)
class Layer:
    name: str
    kind: str  # "base" (the backend), "system" or "home"
    root: Path
    modules: tuple[Path, ...]  # the NixOS or Home Manager modules of the layer, in the order they apply

    @property
    def lib(self) -> Path | None:
        path = self.root / "lib.sh"
        return path if path.is_file() else None

    @property
    def gpu(self) -> bool:
        """A layer that has a file `gpu` asks for a GPU: the host's in a container, a virtual one in a VM."""
        return (self.root / "gpu").is_file()

    @property
    def fixtures_dir(self) -> Path:
        return self.root / "fixtures"

    @property
    def checks_dir(self) -> Path:
        return self.root / "checks"


def discover(box_dir: Path, system: Target, home: Target | None, backend: str = "container") -> list[Layer]:
    """The layer of what the backends share, that of the backend, then that of the system, then that of the home
    (a layer exists when its directory does). `module.nix` of a layer applies to every backend, `<backend>.nix` to
    that one only."""
    if backend not in BACKENDS:
        raise UsageError(f"unknown backend {backend!r} (have: {', '.join(BACKENDS)})")
    base = box_dir / "backends" / backend
    layers = [
        Layer("backends", "base", box_dir / "backends", ()),  # what every backend shares: lib.sh
        Layer(f"backends/{backend}", "base", base, tuple(p for p in [base / "module.nix"] if p.is_file())),
    ]
    targets = [("systems", "system", system)] + ([("homes", "home", home)] if home else [])
    for kind_dir, kind, target in targets:
        root = box_dir / kind_dir / target.attr
        if root.is_dir():
            modules = tuple(p for p in (root / "module.nix", root / f"{backend}.nix") if p.is_file())
            layers.append(Layer(f"{kind_dir}/{target.attr}", kind, root, modules))
    return layers
