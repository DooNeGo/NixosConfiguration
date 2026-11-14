#!/usr/bin/env bash
# PostToolUse(Edit|Write): format a changed .nix file so the Stop lint does not fail on nixfmt --check.
file=$(jq -r '.tool_input.file_path // empty')
case "$file" in
  */hardware-configuration.nix) exit 0 ;;
  *.nix) [ -f "$file" ] && nixfmt "$file" 1>&2 ;;
esac
exit 0
