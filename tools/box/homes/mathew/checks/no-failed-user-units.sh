# shellcheck shell=bash
# requires: desktop-ready (shared)
# A user unit of the desktop session that failed is a finding.
failed=$(systemctl --user --failed --no-legend --plain)
if [ -n "$failed" ]; then
  echo "$failed"
  exit 1
fi
