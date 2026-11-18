#!/usr/bin/env bash
# Build the Home Manager configuration of a TARGET user for the test account `testuser` and activate it there.
# Only home.username and home.homeDirectory change; the target flake and its lock are used as they are.
set -euo pipefail

prog=${0##*/}
repo=$(cd "$(dirname "$0")/.." && pwd)
user=testuser

usage() {
  cat << EOF
Usage: $prog [--with MODULE]... [--build-only] [--force] [--] TARGET

Build homeConfigurations.TARGET of home-config/TARGET (any Linux target, e.g. mathew, openclaw-npm)
as the user $user and activate it over ssh ($user@localhost).

Options:
      --with MODULE  add a Home Manager module file to the configuration (e.g. home-config/testuser/modules/fake-sunshine.nix)
      --build-only   build and print the activation package, do not activate
      --force        activate although the session of $user is running
  -h, --help         show this help
EOF
}

usage_error() {
  echo "$prog: $1" >&2
  echo "Try '$prog --help' for more information." >&2
  exit 2
}

extra=()
build_only=0
force=0
target=
while [ $# -gt 0 ]; do
  case $1 in
    -h | --help)
      usage
      exit 0
      ;;
    --with)
      [ $# -ge 2 ] || usage_error "--with needs a module file"
      extra+=("$2")
      shift
      ;;
    --with=*) extra+=("${1#--with=}") ;;
    --build-only) build_only=1 ;;
    --force) force=1 ;;
    --)
      shift
      [ $# -le 1 ] || usage_error "one TARGET only"
      target=${1:-}
      break
      ;;
    -*) usage_error "unknown option '$1'" ;;
    *)
      [ -z "$target" ] || usage_error "one TARGET only"
      target=$1
      ;;
  esac
  shift
done

[ -n "$target" ] || usage_error "TARGET is required"
[ -f "$repo/home-config/$target/flake.nix" ] || usage_error "no flake home-config/$target"

modules=()
for m in "${extra[@]}"; do
  [ -f "$m" ] || usage_error "no module file '$m'"
  modules+=("$(realpath "$m")")
done

if [ "$build_only" -eq 0 ] && [ "$force" -eq 0 ] && systemctl is-active --quiet "hyprland-headless-$user.service"; then
  echo "$prog: the session of $user is running; stop it first (activation restarts its units) or pass --force" >&2
  exit 1
fi

export TESTUSER_FLAKE="git+file://$repo?dir=home-config/$target"
export TESTUSER_TARGET=$target
export TESTUSER_USER=$user
export TESTUSER_MODULES="${modules[*]:-}"

# The Nix expression reads its inputs from the environment; nothing is substituted by the shell.
# shellcheck disable=SC2016
out=$(nix build --impure --no-link --print-out-paths --expr '
  let
    flake = builtins.getFlake (builtins.getEnv "TESTUSER_FLAKE");
    config = flake.homeConfigurations.${builtins.getEnv "TESTUSER_TARGET"};
    user = builtins.getEnv "TESTUSER_USER";
    extra = builtins.filter (m: m != "") (builtins.split " " (builtins.getEnv "TESTUSER_MODULES"));
  in
  (config.extendModules {
    modules = [
      (
        { lib, ... }:
        {
          home.username = lib.mkForce user;
          home.homeDirectory = lib.mkForce "/home/${user}";
        }
      )
    ] ++ map (m: /. + m) (builtins.filter builtins.isString extra);
  }).activationPackage
')

echo "$out"
# A file the compositor wrote on a first start (hypr/hyprland.lua) would block the activation: keep it as .bak.
[ "$build_only" -eq 1 ] || ssh -o BatchMode=yes "$user@localhost" "HOME_MANAGER_BACKUP_EXT=bak HOME_MANAGER_BACKUP_OVERWRITE=1 $out/activate"
