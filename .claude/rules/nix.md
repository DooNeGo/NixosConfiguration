---
paths:
  - "**/*.nix"
---

# Nix files

- Reach every flake input through `inputs`; take `stable`/`unstable` packages from the overlay in `lib/pkgs.nix` (`pkgs.stable.<x>`), not from extra `pkgs-stable` arguments.
- Group repeated attribute paths into one set (statix `repeated_keys` is on, and the owner prefers grouped keys).
- Format the files you changed with `nixfmt`; `scripts/lint.sh` exits 0 before you report done.
- Look an option up before using or changing it. The local NixOS manual describes every option of the built release: `grep -o '/nix/store[^ ]*index.html' $(which nixos-help)` gives the path, and `options.html` beside it has an `opt-<option path>` anchor (strip tags with `sed 's/<[^>]*>//g'`).
- The manual does not say what a module enables or for whom (`services.sunshine.autoStart` starts the unit for every user), so also read the module: `nix eval --raw .#nixosConfigurations.nixos.pkgs.path` is the nixpkgs tree, the file is the `Declared by` path under `nixos/modules/`.
