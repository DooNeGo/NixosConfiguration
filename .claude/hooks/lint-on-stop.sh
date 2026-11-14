#!/usr/bin/env bash
# Stop: when Nix or shell files changed, scripts/lint.sh must pass before the turn ends (exit 2 sends Claude back once).
[ "$(jq -r '.stop_hook_active // false')" = true ] && exit 0
cd "$CLAUDE_PROJECT_DIR" || exit 0
git status --porcelain -- '*.nix' '*.sh' '*.zsh' | grep -q . || exit 0
scripts/lint.sh 1>&2 || exit 2
