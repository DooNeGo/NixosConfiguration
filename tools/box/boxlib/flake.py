"""The flake that box generates: the targets as inputs, the layers applied by tools/box/flake.nix lib."""

from pathlib import Path

from .layers import SYSTEM_ATTR, Layer
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
    backend: str = "container",
    out_dir: Path | None = None,
) -> str:
    """system_extras and home_extras are file names next to the generated flake.nix. `out_dir` is the host
    directory a VM shares as /out."""

    # Layer modules are read from the box input: a pure evaluation cannot name a path outside the flake sources.
    def modules(kinds: tuple[str, ...], extras: list[str]) -> list[str]:
        paths = [m.relative_to(box_dir) for layer in layers if layer.kind in kinds for m in layer.modules]
        return [f'"${{box}}/{path}"' for path in paths] + [f"./{name}" for name in extras]

    vm = backend == "vm"
    if vm and out_dir is None:
        raise ValueError("a VM needs the host directory it shares as /out")
    system_modules = modules(("base", "system"), system_extras)
    if vm:
        share = f'source = "{out_dir}"; target = "/out"; writable = true;'
        system_modules.append(f"{{ virtualisation.sharedDirectories.out = {{ {share} }}; }}")
        if home:
            # The guest activates the home itself, so its closure has to be registered in the guest's store.
            system_modules.append("{ virtualisation.additionalPaths = [ homePackage ]; }")

    inputs = [
        f'box.url = "{_url(repo, "tools/box")}";',
        f'sys.url = "{_url(repo, system.dir)}";',
    ]
    args = ["box", "sys"]
    system_attr = SYSTEM_ATTR[backend]
    packages = [
        f"{system_attr} = (box.lib.mkSystem {{",
        f"  configuration = sys.{system.output};",
        f"  modules = {_module_list(system_modules)};",
        f"}}).config.system.build.{system_attr};",
    ]
    lets: list[str] = []
    extra_outputs: list[str] = []
    if home:
        inputs.append(f'home.url = "{_url(repo, home.dir)}";')
        args.append("home")
        lets = [
            "homeConfiguration = box.lib.mkHome {",
            f"  configuration = home.{home.output};",
            f"  modules = {_module_list(modules(('home',), home_extras))};",
            "};",
            "homePackage = homeConfiguration.activationPackage;",
        ]
        packages += ["home = homePackage;"]
        extra_outputs = ["lib.username = homeConfiguration.config.home.username;"]
    lines = [
        "{",
        "  inputs = {",
        *("    " + line for line in inputs),
        "  };",
        f"  outputs = {{ {', '.join(args)}, ... }}:",
        "    let",
        *("      " + line for line in lets),
        "    in",
        "    {",
        "      packages.x86_64-linux = {",
        *("        " + line for line in packages),
        "      };",
        *("      " + line for line in extra_outputs),
        "    };",
        "}",
    ]
    return "\n".join(lines) + "\n"
