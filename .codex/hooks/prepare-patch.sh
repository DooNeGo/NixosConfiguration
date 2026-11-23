#!/usr/bin/env bash
# Apply the repository's formatting and Git visibility conventions to Codex patches.
set -euo pipefail

input=$(cat)
root=$(git rev-parse --show-toplevel)
cwd=$(jq -er '.cwd' <<< "$input")
patch=$(jq -er '.tool_input.command' <<< "$input")
cd "$root"
failed=0

while IFS= read -r line; do
  case "$line" in
    '*** Add File: '* | '*** Move to: '*) added=true ;;
    '*** Update File: '*) added=false ;;
    *) continue ;;
  esac

  path=${line#*: }
  [[ "$path" = /* ]] || path="$cwd/$path"
  path=$(realpath -e -- "$path" 2>/dev/null) || continue
  [[ "$path" == "$root/"* && -f "$path" ]] || continue
  path=${path#"$root/"}

  if "$added" && ! git ls-files --error-unmatch -- "$path" >/dev/null 2>&1 \
    && ! git check-ignore -q -- "$path"; then
    if ! git add -N -- "$path"; then
      printf 'Could not register %s with git add -N. Register it before evaluating a flake that uses it.\n' "$path" >&2
      failed=1
    fi
  fi

  case "$path" in
    hardware-configuration.nix | */hardware-configuration.nix) ;;
    *.nix)
      if command -v nixfmt >/dev/null; then
        nixfmt -- "$path" >&2 || failed=1
      else
        nix shell nixpkgs#nixfmt --command nixfmt -- "$path" >&2 || failed=1
      fi
      ;;
  esac
done <<< "$patch"

if [ "$failed" -ne 0 ]; then
  exit 2
fi
