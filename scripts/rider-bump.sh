#!/usr/bin/env bash
# Set the pinned Rider and JetBrains Gateway versions in overlays/rider.nix: version and build number from the
# JetBrains release list, the hash of every system from the .sha256 file next to its download.
set -euo pipefail

prog=${0##*/}
cd "$(dirname "$0")/.."

overlay=overlays/rider.nix
releases_url=https://data.services.jetbrains.com/products/releases

usage() {
  cat << EOF
Usage: $prog [--rider VERSION] [--gateway VERSION] [--dry-run]

Rewrite the version, build number and per-system hashes of Rider and
JetBrains Gateway in $overlay. With no product option both are set to
their latest release; with one, only that product changes.

Options:
      --rider VERSION     Rider version (e.g. 2026.3) or 'latest'
      --gateway VERSION   Gateway version or 'latest'
      --dry-run           print what would be written, change nothing
  -h, --help              show this help
EOF
}

usage_error() {
  echo "$prog: $1" >&2
  echo "Try '$prog --help' for more information." >&2
  exit 2
}

die() {
  echo "$prog: $1" >&2
  exit 1
}

rider=
gateway=
dry_run=0
while [ $# -gt 0 ]; do
  case $1 in
    -h | --help)
      usage
      exit 0
      ;;
    --dry-run) dry_run=1 ;;
    --rider | --gateway)
      [ $# -ge 2 ] || usage_error "option '$1' requires an argument"
      if [ "$1" = --rider ]; then rider=$2; else gateway=$2; fi
      shift
      ;;
    --rider=*) rider=${1#*=} ;;
    --gateway=*) gateway=${1#*=} ;;
    --)
      [ $# -eq 1 ] || usage_error "unexpected argument '$2'"
      ;;
    -*) usage_error "unknown option '$1'" ;;
    *) usage_error "unexpected argument '$1'" ;;
  esac
  shift
done
if [ -z "$rider" ] && [ -z "$gateway" ]; then
  rider=latest
  gateway=latest
fi
for version in "$rider" "$gateway"; do
  [[ -z $version || $version == latest || $version =~ ^[0-9]+(\.[0-9]+)+$ ]] \
    || usage_error "invalid version '$version'"
done

# Prints "<version> <build>" of the wanted release.
release() {
  local code=$1 want=$2 found
  found=$(curl -fsS "$releases_url?code=$code&type=release" | jq -r --arg code "$code" --arg want "$want" '
    .[$code] | (if $want == "latest" then .[0] else (map(select(.version == $want)) | .[0]) end)
    | select(. != null) | "\(.version) \(.build)"')
  [ -n "$found" ] || die "no $code release '$want' in the JetBrains release list"
  echo "$found"
}

sri() {
  local hex
  hex=$(curl -fsSL "$1.sha256" | awk '{ print $1; exit }')
  [[ $hex =~ ^[0-9a-f]{64}$ ]] || die "no sha256 at $1.sha256"
  nix hash convert --hash-algo sha256 --to sri "$hex"
}

# Rewrites <product>Version, <product>BuildNumber and both hashes of <product>Sources; fails unless all four are found.
rewrite() {
  awk -v product="$1" -v version="$2" -v build="$3" -v linux="$4" -v darwin="$5" '
    function set(value) { sub(/"[^"]*"/, "\"" value "\""); changed++ }
    $1 == product "Version" { set(version) }
    $1 == product "BuildNumber" { set(build) }
    $1 == product "Sources" { inside = 1 }
    inside && $1 == "x86_64-linux" { os = "linux" }
    inside && $1 == "aarch64-darwin" { os = "darwin" }
    inside && $1 == "hash" { set(os == "linux" ? linux : darwin) }
    inside && /^  };/ { inside = 0 }
    { print }
    END { exit changed == 4 ? 0 : 1 }
  '
}

tmp=$(mktemp "$overlay.XXXXXX")
trap 'rm -f "$tmp" "$tmp.new"' EXIT
cp "$overlay" "$tmp"

bump() {
  local product=$1 code=$2 want=$3 base=$4 version build linux darwin
  read -r version build < <(release "$code" "$want")
  linux=$(sri "$base-$version.tar.gz")
  darwin=$(sri "$base-$version-aarch64.dmg")
  echo "$product $version ($build)"
  rewrite "$product" "$version" "$build" "$linux" "$darwin" < "$tmp" > "$tmp.new" \
    || die "$overlay: the $product pin does not have the expected layout"
  mv "$tmp.new" "$tmp"
}

[ -z "$rider" ] || bump rider RD "$rider" https://download.jetbrains.com/rider/JetBrains.Rider
[ -z "$gateway" ] || bump gateway GW "$gateway" https://download.jetbrains.com/idea/gateway/JetBrainsGateway

if cmp -s "$tmp" "$overlay"; then
  echo "$overlay is already at these versions"
elif [ "$dry_run" -eq 1 ]; then
  diff -u "$overlay" "$tmp" || true
else
  chmod --reference="$overlay" "$tmp"
  mv "$tmp" "$overlay"
  echo "$overlay updated"
fi
