#!/usr/bin/env bash
# Read-only check of the generated OpenClaw config: build, config validate,
# doctor --lint --severity-min error. Runs on isolated temp state (removed on
# exit); never touches ~/.openclaw. Run from anywhere; operates on this flake.
# Exit 0 = build and validate pass and doctor reports no errors. Any failing
# step exits non-zero; doctor output is shown only when that step fails.
set -euo pipefail

flake_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
state=$(mktemp -d)
trap 'rm -rf "$state"' EXIT

echo "== build"
out=$(nix build "$flake_dir#homeConfigurations.openclaw.activationPackage" \
  --no-link --print-out-paths)
refs=$(nix-store -q --references "$out") || { echo "nix-store -q --references failed for $out" >&2; exit 1; }
cfg=$(grep -m1 openclaw-default.json <<<"$refs" || true)
[ -n "$cfg" ] || { echo "openclaw-default.json not found in build closure" >&2; exit 1; }

export OPENCLAW_STATE_DIR=$state OPENCLAW_CONFIG_PATH=$cfg
# openclaw leaks openclaw-plugin-build-* dirs under os.tmpdir(); keep them in $state so the EXIT trap removes them.
export TMPDIR=$state

echo "== config validate"
openclaw config validate

echo "== doctor --lint"
lint_log="$state/doctor-lint.log"
if ! openclaw doctor --lint --severity-min error >"$lint_log" 2>&1; then
  cat "$lint_log" >&2
  exit 1
fi

echo "== ok"
