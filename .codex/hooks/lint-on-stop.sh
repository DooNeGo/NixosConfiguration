#!/usr/bin/env bash
set -euo pipefail

input=$(cat)
if [ "$(jq -r '.stop_hook_active // false' <<< "$input")" = true ]; then
  exit 0
fi

cd "$(git rev-parse --show-toplevel)"
if [ -z "$(git status --porcelain -- '*.nix' '*.sh' '*.zsh' tools/box)" ]; then
  exit 0
fi

scripts/lint.sh >&2 || exit 2
