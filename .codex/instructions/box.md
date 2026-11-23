# tools/box

- A layer overrides the real configuration and never copies it: a copy drifts, and the box passes while the real one differs. A unit that fails in the box: `docs/box.md`, Layers (does it need testing: off through its `enable` option, or an override that keeps its meaning). Raising the container's privileges (`--cap-add`, `--device`, `--security-opt`, groups) is off by default: ask the owner before adding any.
- Container or VM: the container is the default; take the VM (`--backend vm`) when a check needs a whole boot, the real SDDM, udev, sysfs or mounts (`docs/box.md`, Container or VM).
- A layer file `module.nix` applies to both backends, `container.nix` or `vm.nix` to one; a check runs on every backend unless it has a `# backends:` line; a command of the session user goes through `box_user`.
- A fixture has `setup` and `teardown` (both required) and an optional `requires`; a check passes with exit 0 and names its fixtures in `# requires:` lines; the `lib.sh` of every layer runs before each script.
- A new file in `tools/box` needs `git add -N`: the generated flake reads git, and `box` refuses untracked files.
- Done when `scripts/lint.sh`, `python3 -m unittest discover -s tools/box/tests -t tools/box` and `tools/box/box test --system nixos --home mathew` (and again with `--backend vm`) have run and their output is shown.
