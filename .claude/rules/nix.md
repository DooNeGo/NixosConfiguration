---
paths:
  - "**/*.nix"
---

# Nix files

- Reach every flake input through `inputs`; take `stable`/`unstable` packages from the overlay in `lib/pkgs.nix` (`pkgs.stable.<x>`), not from extra `pkgs-stable` arguments.
- Group repeated attribute paths into one set (statix `repeated_keys` is on, and the owner prefers grouped keys).
- Format the files you changed with `nixfmt`; `scripts/lint.sh` exits 0 before you report done.
