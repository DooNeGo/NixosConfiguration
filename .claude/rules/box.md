---
paths:
  - "tools/box/**"
---

# tools/box

- A layer overrides the real configuration and never copies it: a copy drifts, and the box passes while the real one differs. A unit that fails in the container: `docs/box.md`, Layers.
- A fixture has `setup` and `teardown` (both required) and an optional `requires`; a check passes with exit 0 and names its fixtures in `# requires:` lines; the `lib.sh` of every layer runs before each script.
- A new file in `tools/box` needs `git add -N`: the generated flake reads git, and `box` refuses untracked files.
- Done when `scripts/lint.sh`, `python3 -m unittest discover -s tools/box/tests -t tools/box` and `tools/box/box test --system nixos --home mathew` have run and their output is shown.
