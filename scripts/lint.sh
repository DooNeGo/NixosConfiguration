#!/usr/bin/env bash
# Lint every .nix file in the repo (all flakes): deadnix (unused code) and statix (anti-patterns).
# Config: statix.toml. hardware-configuration.nix is generated and excluded from both.
# Usage: scripts/lint.sh   (deadnix and statix are installed system-wide, see system-config/configuration.nix;
#                           until they are, it falls back to `nix shell`)
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v deadnix > /dev/null || ! command -v statix > /dev/null; then
  # run once inside `nix shell`; if the tools are still missing there, fail instead of re-executing forever
  if [ -n "${LINT_IN_NIX_SHELL:-}" ]; then
    echo "lint.sh: deadnix/statix not found even inside nix shell" >&2
    exit 1
  fi
  LINT_IN_NIX_SHELL=1 exec nix shell nixpkgs#deadnix nixpkgs#statix --command "$0" "$@"
fi

deadnix --fail . --exclude system-config/hardware-configuration.nix
statix check .
