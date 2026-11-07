#!/usr/bin/env bash
# Estimate how well each directory under PATH compresses with zstd -1, without writing anything.
# Use it to pick the directories worth recompressing (scripts/btrfs-recompress.sh): the interesting ones are
# those that are stored uncompressed now (compare with `sudo compsize -x <dir>`) but compress well here.
#
# Usage: scripts/btrfs-compress-estimate.sh [--depth N] PATH...
#   --depth N  report the entries N levels below each PATH (default 1), e.g.
#              scripts/btrfs-compress-estimate.sh /games/SteamLibrary/steamapps/common
# Reads every file once at idle IO priority (about as long as copying the data); needs zstd and tar in PATH.
set -euo pipefail

depth=1
paths=()
while [ $# -gt 0 ]; do
  case "$1" in
    --depth) depth="${2:?}"; shift ;;
    -h | --help) sed -n '2,10p' "$0"; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) paths+=("$1") ;;
  esac
  shift
done
[ ${#paths[@]} -gt 0 ] || { echo "no PATH given (see --help)" >&2; exit 2; }
command -v zstd > /dev/null || { echo "zstd not found" >&2; exit 1; }

rows=$(mktemp)
trap 'rm -f "$rows"' EXIT

for root in "${paths[@]}"; do
  while IFS= read -r -d '' entry; do
    # unreadable files only make the numbers slightly smaller, they must not stop the run
    raw=$({ du -sb -- "$entry" 2> /dev/null || true; } | cut -f1)
    comp=$({ ionice -c3 nice -n19 tar -cf - -- "$entry" 2> /dev/null || true; } | zstd -1 -T4 -c | wc -c)
    # name, raw bytes, zstd bytes, estimated saving in bytes
    printf '%s\t%s\t%s\t%s\n' "$entry" "$raw" "$comp" "$((raw - comp))" >> "$rows"
    echo "done: $entry" >&2
  done < <(find "$root" -mindepth "$depth" -maxdepth "$depth" -print0)
done

printf '%-60s %10s %10s %7s %10s\n' ENTRY RAW_GiB ZSTD_GiB RATIO SAVED_GiB
sort -t$'\t' -k4,4nr "$rows" | awk -F'\t' '
  { raw += $2; comp += $3
    printf "%-60.60s %10.2f %10.2f %6.0f%% %10.2f\n", $1, $2/2^30, $3/2^30, ($2 ? 100*$3/$2 : 100), $4/2^30 }
  END { printf "%-60s %10.2f %10.2f %6.0f%% %10.2f\n", "TOTAL", raw/2^30, comp/2^30, (raw ? 100*comp/raw : 100), (raw-comp)/2^30 }'
