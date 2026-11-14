#!/usr/bin/env bash
# Update the lock of every flake in the repo with `nix flake update` and check that each flake still builds
# (the darwin outputs are only evaluated: they cannot be built on this host).
set -euo pipefail

prog=${0##*/}
cd "$(dirname "$0")/.."

all_flakes=(nixos darwin DooNeGo mathew openclaw-npm kokoro)

usage() {
  cat << EOF
Usage: $prog [--check] [--] [FLAKE...]

Update flake.lock of each FLAKE with 'nix flake update', then build it
(darwin and DooNeGo: evaluate). Every flake is processed even when an
earlier one fails. Exit status is 0 only when all of them build.

Flakes: ${all_flakes[*]} (default: all)

Options:
      --check   do not update the locks, only build
  -h, --help    show this help
EOF
}

usage_error() {
  echo "$prog: $1" >&2
  echo "Try '$prog --help' for more information." >&2
  exit 2
}

flake_dir() {
  case $1 in
    nixos | darwin) echo "system-config/$1" ;;
    DooNeGo | mathew | openclaw-npm) echo "home-config/$1" ;;
    kokoro) echo "kokoro" ;;
    *) return 1 ;;
  esac
}

verify() {
  case $1 in
    nixos) nix build --no-link ./system-config/nixos#nixosConfigurations.nixos.config.system.build.toplevel ;;
    darwin) nix eval --raw ./system-config/darwin#darwinConfigurations.macbook-air-m1.config.system.build.toplevel.drvPath ;;
    DooNeGo) nix eval --raw ./home-config/DooNeGo#homeConfigurations.DooNeGo.activationPackage.drvPath ;;
    # the same derivation `home-manager build` makes, without the ./result link
    mathew | openclaw-npm) nix build --no-link "./home-config/$1#homeConfigurations.$1.activationPackage" ;;
    kokoro) nix build --no-link ./kokoro#kokoro-ru ;;
  esac
}

update=1
flakes=()
while [ $# -gt 0 ]; do
  case $1 in
    -h | --help)
      usage
      exit 0
      ;;
    --check) update=0 ;;
    --)
      shift
      flakes+=("$@")
      break
      ;;
    -*) usage_error "unknown option '$1'" ;;
    *) flakes+=("$1") ;;
  esac
  shift
done
[ ${#flakes[@]} -gt 0 ] || flakes=("${all_flakes[@]}")
for flake in "${flakes[@]}"; do
  flake_dir "$flake" > /dev/null || usage_error "unknown flake '$flake'"
done

logs=$(mktemp -d "${TMPDIR:-/tmp}/flake-update.XXXXXX")
failed=()
summary=()

for flake in "${flakes[@]}"; do
  dir=$(flake_dir "$flake")
  log=$logs/$flake.log
  lock_state="not updated"
  echo "== $flake"

  if [ "$update" -eq 1 ]; then
    before=$(sha256sum < "$dir/flake.lock")
    if ! nix flake update --flake "./$dir" > "$log" 2>&1; then
      tail -n 30 "$log"
      failed+=("$flake")
      summary+=("$flake: UPDATE FAILED ($log)")
      continue
    fi
    # nix reports each changed input as "• Updated input 'x':" followed by the old and the new revision
    grep -A2 -E "(Updated|Added|Removed) input" "$log" || true
    if [ "$before" = "$(sha256sum < "$dir/flake.lock")" ]; then
      lock_state="lock unchanged"
    else
      lock_state="lock updated"
    fi
  fi

  if verify "$flake" >> "$log" 2>&1; then
    summary+=("$flake: ok, $lock_state")
  else
    tail -n 30 "$log"
    failed+=("$flake")
    summary+=("$flake: BUILD FAILED, $lock_state ($log)")
  fi
done

echo
printf '%s\n' "${summary[@]}"
if [ ${#failed[@]} -gt 0 ]; then
  echo "$prog: failed: ${failed[*]}" >&2
  exit 1
fi
rm -rf "$logs"
