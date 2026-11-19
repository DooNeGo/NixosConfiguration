"""The flake that box generates: the targets as inputs, the layers applied by tools/box/flake.nix lib."""

from pathlib import Path

from .layers import Layer
from .targets import Target


def _url(repo: Path, directory: str) -> str:
    return f"git+file://{repo}?dir={directory}"


def _module_list(items: list[str]) -> str:
    return "[ " + " ".join(items) + " ]"


def render(
    repo: Path,
    box_dir: Path,
    system: Target,
    home: Target | None,
    layers: list[Layer],
    system_extras: list[str],
    home_extras: list[str],
) -> str:
    """system_extras and home_extras are file names next to the generated flake.nix."""

    # Layer modules are read from the box input: a pure evaluation cannot name a path outside the flake sources.
    def modules(kind: str, extras: list[str]) -> list[str]:
        paths = [layer.module.relative_to(box_dir) for layer in layers if layer.module and layer.kind == kind]
        return [f'"${{box}}/{path}"' for path in paths] + [f"./{name}" for name in extras]

    system_modules = modules("container", []) + modules("system", system_extras)

    inputs = [
        f'box.url = "{_url(repo, "tools/box")}";',
        f'sys.url = "{_url(repo, system.dir)}";',
    ]
    args = ["box", "sys"]
    packages = [
        "toplevel = (box.lib.mkSystem {",
        f"  configuration = sys.{system.output};",
        f"  modules = {_module_list(system_modules)};",
        "}).config.system.build.toplevel;",
    ]
    if home:
        inputs.append(f'home.url = "{_url(repo, home.dir)}";')
        args.append("home")
        packages += [
            "home = (box.lib.mkHome {",
            f"  configuration = home.{home.output};",
            f"  modules = {_module_list(modules('home', home_extras))};",
            "}).activationPackage;",
        ]
    lines = [
        "{",
        "  inputs = {",
        *("    " + line for line in inputs),
        "  };",
        f"  outputs = {{ {', '.join(args)}, ... }}: {{",
        "    packages.x86_64-linux = {",
        *("      " + line for line in packages),
        "    };",
        "  };",
        "}",
    ]
    return "\n".join(lines) + "\n"
