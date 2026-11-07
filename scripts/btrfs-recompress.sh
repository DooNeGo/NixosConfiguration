#!/usr/bin/env bash
# Recompress existing btrfs data with zstd:-1 (the mount option only affects NEW writes).
#
# Uses `btrfs filesystem defragment -czstd -L -1` (needs kernel >= 6.15 and btrfs-progs with --level).
# Every PATH is cut into work units no bigger than --max-unit-gib (a big directory is split into its own files
# plus its subdirectories, recursively), so free space is checked often and an interrupted run resumes cheaply.
# Nested subvolumes and other mounts below a PATH are never entered (e.g. ~/mnt, /var/lib/nocow, podman layers).
#
# WARNING - read docs/btrfs.md first:
#   * defragment breaks reflinks: data shared by `cp --reflink`, snapshots or dedup is copied, so used
#     space can GROW. Run it BEFORE the btrbk backups are enabled (a snapshot would keep the old copies).
#   * the disk is close to full; every file is rewritten, so keep --min-free-gib generous.
#
# Usage: sudo scripts/btrfs-recompress.sh [--run] [--min-free-gib N] [--max-unit-gib N] [--state FILE] PATH...
#   default is a dry run that only prints the work units.
#   whole disk (everything worth it): sudo scripts/btrfs-recompress.sh --run --min-free-gib 100 /games /home
set -euo pipefail

run=0
min_free_gib=60
max_unit_gib=25
state=/var/tmp/btrfs-recompress.done
paths=()

while [ $# -gt 0 ]; do
  case "$1" in
    --run) run=1 ;;
    --min-free-gib) min_free_gib="${2:?}"; shift ;;
    --max-unit-gib) max_unit_gib="${2:?}"; shift ;;
    --state) state="${2:?}"; shift ;;
    -h | --help) sed -n '2,17p' "$0"; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) paths+=("$1") ;;
  esac
  shift
done
[ ${#paths[@]} -gt 0 ] || { echo "no PATH given (see --help)" >&2; exit 2; }

if [ "$run" = 1 ] && [ "$(id -u)" -ne 0 ]; then
  echo "--run needs root" >&2
  exit 1
fi
btrfs filesystem defragment --help 2>&1 | grep -q -- '--level' \
  || { echo "this btrfs-progs has no defragment --level" >&2; exit 1; }

max_bytes=$((max_unit_gib * 1024 * 1024 * 1024))
mode=DRY-RUN
[ "$run" = 1 ] && mode=RUN
touch "$state" 2>/dev/null || true
log() { printf '%s %s\n' "$(date +%T)" "$*"; }

free_gib() { # estimated free space of the filesystem holding $1, in GiB
  btrfs filesystem usage -b "$1" 2>/dev/null | awk -F: '/Free \(estimated\)/ { split($2, a, " "); printf "%d", a[1] / 2^30 }'
}

tree_bytes() { # apparent size of a directory tree, staying on one filesystem; unreadable parts count as 0
  { du -sbx -- "$1" 2>/dev/null || true; } | cut -f1
}

# Prints work units as NUL-separated triples: kind, path, size.
#   D = a whole directory tree (defragment -r)    F = only the files directly inside a directory
emit_units() {
  local dir=$1 size sub
  size=$(tree_bytes "$dir")
  size=${size:-0}
  if [ "$size" -le "$max_bytes" ]; then
    printf 'D\0%s\0%s\0' "$dir" "$size"
    return
  fi
  if [ -n "$(find "$dir" -xdev -mindepth 1 -maxdepth 1 -type f -print -quit)" ]; then
    printf 'F\0%s\0%s\0' "$dir" 0
  fi
  while IFS= read -r -d '' sub; do
    emit_units "$sub"
  done < <(find "$dir" -xdev -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
}

enough_space() { # $1 = path on the filesystem, $2 = what is about to be processed
  if [ "$(free_gib "$1")" -lt "$min_free_gib" ]; then
    log "STOP: free space below $min_free_gib GiB before $2 (re-run to resume)"
    return 1
  fi
}

defrag() {
  ionice -c3 nice -n19 btrfs filesystem defragment -czstd -L -1 -t 128M "$@"
}

for root in "${paths[@]}"; do
  [ "$(stat -f -c %T "$root")" = btrfs ] || { echo "$root is not on btrfs" >&2; exit 1; }
  log "== $root: $mode, free $(free_gib "$root") GiB (minimum $min_free_gib), unit limit $max_unit_gib GiB"
  while IFS= read -r -d '' kind && IFS= read -r -d '' path && IFS= read -r -d '' size; do
    key="$kind:$path"
    if grep -qxF -- "$key" "$state" 2>/dev/null; then
      log "skip (done): $key"
      continue
    fi
    if [ "$run" != 1 ]; then
      if [ "$kind" = D ]; then
        log "would defrag [D] $path ($((size / 1024 / 1024 / 1024)) GiB)"
      else
        log "would defrag [F] files directly in $path"
      fi
      continue
    fi
    case "$kind" in
      D)
        enough_space "$root" "$key" || exit 3
        log "defrag [D] $path ($((size / 1024 / 1024 / 1024)) GiB)"
        defrag -r -- "$path"
        ;;
      F)
        log "defrag [F] files directly in $path"
        # file by file: big pak files can be tens of GiB, so check free space before each one
        while IFS= read -r -d '' file; do
          enough_space "$root" "$file" || exit 3
          defrag -- "$file"
        done < <(find "$path" -xdev -mindepth 1 -maxdepth 1 -type f -print0)
        ;;
    esac
    printf '%s\n' "$key" >> "$state"
  done < <(emit_units "$root")
done
log "finished"
