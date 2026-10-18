#!/usr/bin/env bash
# Read-only check of an OpenClaw (npm) config: config validate + doctor --lint
# on an isolated temp state dir. Never touches ~/.openclaw.
# Repo copy: home-config/openclaw-npm/scripts/config-check.sh (keep in sync with the workspace original).
# Usage: config-check.sh [path/to/openclaw.json]   (default: ~/.openclaw/openclaw.json)
# Exit 0 = validate passes and doctor reports no errors.
set -euo pipefail
src=${1:-$HOME/.openclaw/openclaw.json}
[ -r "$src" ] || { echo "config not readable: $src" >&2; exit 1; }
state=$(mktemp -d)
trap 'rm -rf "$state"' EXIT
cp "$src" "$state/openclaw.json"
export OPENCLAW_STATE_DIR=$state OPENCLAW_CONFIG_PATH=$state/openclaw.json TMPDIR=$state
echo "== config validate"
openclaw config validate
echo "== doctor --lint"
log="$state/doctor-lint.log"
if ! openclaw doctor --lint --severity-min error >"$log" 2>&1; then cat "$log" >&2; exit 1; fi
echo "== ok"
