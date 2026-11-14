---
paths:
  - "**/*.nix"
---

# Nix files

- Reach every flake input through `inputs`; take stable-channel packages from the overlay in `lib/pkgs.nix` (`pkgs.stable.<x>`), not from an extra `pkgs-stable` argument.
- Group repeated attribute paths into one set (statix `repeated_keys` is on, and the owner prefers grouped keys).
- A hook formats `.nix` files you write or edit with `nixfmt`; `scripts/lint.sh` exits 0 before you report done.
- `mcp__nixos` searches the upstream channels, not the pinned release: use it to find packages, and check an option against the local manual below.
- Look an option up before using or changing it. The local NixOS manual describes every option of the built release: `grep -o '/nix/store[^ ]*index.html' $(which nixos-help)` gives the path, and `options.html` beside it has an `opt-<option path>` anchor (strip tags with `sed 's/<[^>]*>//g'`).
- The manual does not say what a module enables or for whom (`services.sunshine.autoStart` starts the unit for every user), so also read the module: `nix eval --raw ./system-config/nixos#nixosConfigurations.nixos.pkgs.path` is the nixpkgs tree, the file is the `Declared by` path under `nixos/modules/`.
