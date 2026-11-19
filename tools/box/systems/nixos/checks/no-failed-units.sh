# shellcheck shell=bash
# The container reaches `running` or `degraded` after boot; a failed unit is a finding.
failed=$(systemctl --failed --no-legend --plain)
if [ -n "$failed" ]; then
  echo "$failed"
  exit 1
fi
