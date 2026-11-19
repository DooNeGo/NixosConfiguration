"""Layers: the directories of tools/box that hold the overrides, fixtures and checks of one target."""

from dataclasses import dataclass
from pathlib import Path

from .targets import Target


@dataclass(frozen=True)
class Layer:
    name: str
    kind: str  # "container", "system" or "home"
    root: Path
    module: Path | None  # the NixOS or Home Manager module of the layer, if it has one

    @property
    def lib(self) -> Path | None:
        path = self.root / "lib.sh"
        return path if path.is_file() else None

    @property
    def gpu(self) -> bool:
        """A layer that has a file `gpu` asks for the host GPU and the video group."""
        return (self.root / "gpu").is_file()

    @property
    def fixtures_dir(self) -> Path:
        return self.root / "fixtures"

    @property
    def checks_dir(self) -> Path:
        return self.root / "checks"


def discover(box_dir: Path, system: Target, home: Target | None) -> list[Layer]:
    """container.nix, then the layer of the system, then that of the home (a layer exists when its directory does)."""
    layers = [Layer("container", "container", box_dir, box_dir / "container.nix")]
    targets = [("systems", "system", system)] + ([("homes", "home", home)] if home else [])
    for kind_dir, kind, target in targets:
        root = box_dir / kind_dir / target.attr
        if root.is_dir():
            module = root / "module.nix"
            layers.append(Layer(f"{kind_dir}/{target.attr}", kind, root, module if module.is_file() else None))
    return layers
