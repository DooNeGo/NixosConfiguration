#!/usr/bin/env bash
# PostToolUse(Edit|Write): format a changed .nix file so the Stop lint does not fail on nixfmt --check.
# Exit 2 hands stderr to Claude; exit 0 would hide a missing tool or a file nixfmt cannot parse.
file=$(jq -r '.tool_input.file_path // empty') || {
  echo "format-nix.sh: cannot read the hook input with jq" >&2
  exit 2
}
case "$file" in
  */hardware-configuration.nix) exit 0 ;;
  *.nix) [ -f "$file" ] || exit 0 ;;
  *) exit 0 ;;
esac
if command -v nixfmt > /dev/null; then
  nixfmt "$file" 1>&2
else
  nix shell nixpkgs#nixfmt --command nixfmt "$file" 1>&2
fi || {
  echo "format-nix.sh: $file was not formatted, the reason is above" >&2
  exit 2
}
