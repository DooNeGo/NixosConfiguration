#!/usr/bin/env bash
# Lint every .nix file in the repo (all flakes): deadnix (unused code), statix (anti-patterns), nixfmt (formatting),
# every tracked .sh file with shellcheck, every .zsh file with zsh -n (shellcheck cannot parse zsh) and tools/box plus the sing-box decoder with ruff. Config: statix.toml. hardware-configuration.nix is generated and excluded.
# Usage: scripts/lint.sh   (the tools are installed system-wide, see system-config/nixos/configuration.nix;
#                           until they are, it falls back to `nix shell`)
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v deadnix > /dev/null || ! command -v statix > /dev/null || ! command -v nixfmt > /dev/null \
  || ! command -v shellcheck > /dev/null || ! command -v ruff > /dev/null \
  || ! command -v zsh > /dev/null; then
  # run once inside `nix shell`; if the tools are still missing there, fail instead of re-executing forever
  if [ -n "${LINT_IN_NIX_SHELL:-}" ]; then
    echo "lint.sh: deadnix/statix/nixfmt/shellcheck/ruff/zsh not found even inside nix shell" >&2
    exit 1
  fi
  LINT_IN_NIX_SHELL=1 exec nix shell nixpkgs#deadnix nixpkgs#statix nixpkgs#nixfmt nixpkgs#shellcheck nixpkgs#ruff nixpkgs#zsh --command "$0" "$@"
fi

deadnix --fail . --exclude system-config/nixos/hardware-configuration.nix
statix check .
git ls-files -z '*.nix' ':!system-config/nixos/hardware-configuration.nix' | xargs -0 nixfmt --check
git ls-files -z '*.sh' | xargs -0 shellcheck
git ls-files -z '*.zsh' | xargs -0 -n1 zsh -n
# Fixtures have no extension; they use the helpers and variables of the lib.sh that runs before them (SC2154).
git ls-files -z 'tools/box/*/fixtures/*/setup' 'tools/box/*/fixtures/*/teardown' | xargs -0 shellcheck -e SC2154
# tools/box/box has no .py extension: ruff lints a file named on the command line regardless.
ruff check tools/box tools/box/box
ruff format --check tools/box tools/box/box
ruff check --config tools/box/ruff.toml system-config/nixos/sing-box
ruff format --check --config tools/box/ruff.toml system-config/nixos/sing-box
