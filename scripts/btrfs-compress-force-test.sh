#!/usr/bin/env bash
# btrfs write benchmark: compress vs compress-force at several zstd levels and writer counts.
# Run as a normal user (sudo is called inside). Source data is staged in tmpfs, so only the write is timed.
# The remount changes compression for the WHOLE filesystem while the test runs; the original option is restored on exit.
#
# Usage: scripts/btrfs-compress-force-test.sh [OPTIONS]
#   --levels LIST    zstd levels to test, comma or space separated (default: -2,-1,1,2)
#   --writers LIST   parallel writer counts (default: 1,3,6)
#   --modes LIST     compress and/or compress-force (default: both)
#   --repeats N      runs per combination (default: 1)
#   --dataset SPEC   NAME|SOURCE|MAX_GIB, repeatable (default: Phasmophobia, 20 GiB, and World of Tanks Blitz)
#   --common DIR     directory of the default datasets (default: /games/SteamLibrary/steamapps/common)
#   --mount PATH     filesystem to remount and write to (default: /home)
#   --dest DIR       where the data is written (default: ~/compress-test)
#   --ram DIR        tmpfs staging area (default: /tmp/compress-test-src)
#   --csv FILE       raw results (default: ~/compress-test.csv)
#   --md FILE        markdown tables (default: ~/compress-test.md)
#   --report         rebuild the markdown tables from the CSV and exit
#   --dry            skip remount, compsize and drop_caches (tests the script's own logic)
#   -h, --help       show this text; --opt=VALUE works too
set -euo pipefail

prog=${0##*/}
usage() {
  [[ $# -eq 0 ]] || echo "$prog: $*" >&2
  echo "Try '$prog --help' for more information." >&2
  exit 2
}
# The leading comment block without the shebang and the "# " prefix.
help() { sed -n '2,/^[^#]/{/^[^#]/!s/^# \{0,1\}//p}' "$0"; }
need_arg() { [[ $# -ge 2 ]] || usage "option '$1' requires an argument"; }
is_uint() { [[ $1 =~ ^[0-9]+$ ]]; }
is_int() { [[ $1 =~ ^-?[0-9]+$ ]]; }
words() { tr ',' ' ' <<<"$1"; } # list options take commas or spaces

# --opt=value becomes --opt value, up to a "--".
args=()
for a in "$@"; do
  if [[ $a == -- ]]; then args+=("$@"); break; fi
  case $a in
    --*=*) args+=("${a%%=*}" "${a#*=}") ;;
    *) args+=("$a") ;;
  esac
  shift
done
set -- "${args[@]}"

MNT=/home
DEST=
RAM=/tmp/compress-test-src
OUT_CSV=$HOME/compress-test.csv
OUT_MD=$HOME/compress-test.md
DRY=0
REPORT=0
LEVELS="-2 -1 1 2"
WRITERS="1 3 6"
REPEATS=1
MODES="compress compress-force"
COMMON=/games/SteamLibrary/steamapps/common
DATASETS=
while [[ $# -gt 0 ]]; do
  case $1 in
    --levels) need_arg "$@"; LEVELS=$(words "$2"); shift ;;
    --writers) need_arg "$@"; WRITERS=$(words "$2"); shift ;;
    --modes) need_arg "$@"; MODES=$(words "$2"); shift ;;
    --repeats) need_arg "$@"; REPEATS=$2; shift ;;
    --dataset) need_arg "$@"; DATASETS+="${DATASETS:+$'\n'}$2"; shift ;;
    --common) need_arg "$@"; COMMON=$2; shift ;;
    --mount) need_arg "$@"; MNT=$2; shift ;;
    --dest) need_arg "$@"; DEST=$2; shift ;;
    --ram) need_arg "$@"; RAM=$2; shift ;;
    --csv) need_arg "$@"; OUT_CSV=$2; shift ;;
    --md) need_arg "$@"; OUT_MD=$2; shift ;;
    --report) REPORT=1 ;;
    --dry) DRY=1 ;;
    -h | --help) help; exit 0 ;;
    -*) usage "unknown option '$1'" ;;
    *) usage "unexpected argument '$1'" ;;
  esac
  shift
done

# Checked before anything is remounted.
is_uint "$REPEATS" && [[ $REPEATS -gt 0 ]] || usage "--repeats needs a positive whole number, got '$REPEATS'"
read -ra _w <<<"$WRITERS"
read -ra _l <<<"$LEVELS"
read -ra _m <<<"$MODES"
[[ ${#_w[@]} -gt 0 ]] || usage "--writers is empty"
[[ ${#_l[@]} -gt 0 ]] || usage "--levels is empty"
[[ ${#_m[@]} -gt 0 ]] || usage "--modes is empty"
for v in "${_w[@]}"; do is_uint "$v" && [[ $v -gt 0 ]] || usage "--writers needs positive whole numbers, got '$v'"; done
for v in "${_l[@]}"; do is_int "$v" || usage "--levels needs whole numbers, got '$v'"; done
for v in "${_m[@]}"; do
  [[ $v == compress || $v == compress-force ]] || usage "--modes takes compress and compress-force, got '$v'"
done
if [[ -z $DATASETS ]]; then
  DATASETS="phasmophobia|$COMMON/Phasmophobia|20
blitz|$COMMON/World of Tanks Blitz|1024"
fi
while IFS='|' read -r _ds _src _cap _extra; do
  [[ -n $_ds && -n $_src && -z $_extra ]] && is_uint "$_cap" && [[ $_cap -gt 0 ]] ||
    usage "--dataset needs NAME|SOURCE|MAX_GIB, got '$_ds|$_src|$_cap${_extra:+|$_extra}'"
done <<<"$DATASETS"
if [[ -z $DEST ]]; then
  if ((DRY)); then DEST=/dev/shm/compress-test-dest; else DEST=$HOME/compress-test; fi
fi

# Markdown tables from the CSV (awk only: the benchmark user has no python in PATH)
report() {
  awk -F, '
    function sort_desc(a, n,   i, j, t) { for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++) if (a[j] + 0 > a[i] + 0) { t = a[i]; a[i] = a[j]; a[j] = t } }
    function sort_asc(a, n,   i, j, t) { for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++) if (a[j] + 0 < a[i] + 0) { t = a[i]; a[i] = a[j]; a[j] = t } }
    function speeds(ds, mode, lvl,   k) {
      for (k = 1; k <= nw; k++)
        if ((ds, mode, lvl, wl[k]) in sec) printf " %.2f |", logical[ds] / (sec[ds, mode, lvl, wl[k]] / cnt[ds, mode, lvl, wl[k]]) / 2^30; else printf " |"
    }
    function row(ds, name, mode, lvl,   d) {
      d = disk[ds, mode, lvl, wl[1]] / cnt[ds, mode, lvl, wl[1]]
      printf "| %s | %.1f | %d%% |", name, d / 2^30, 100 * d / logical[ds]
      speeds(ds, mode, lvl)
      printf "\n"
    }
    NR == 1 { next }
    { if (!($1 in ds_seen)) { ds_seen[$1] = 1; dl[++nd] = $1 }
      if (!($2 in w_seen)) { w_seen[$2] = 1; wl[++nw] = $2 }
      if ($4 != "" && !($4 in l_seen)) { l_seen[$4] = 1; ll[++nl] = $4 }
      logical[$1] = $6; sec[$1, $3, $4, $2] += $5; disk[$1, $3, $4, $2] += $7; cnt[$1, $3, $4, $2]++ }
    END {
      sort_asc(wl, nw); sort_desc(ll, nl)
      for (i = 1; i <= nd; i++) {
        ds = dl[i]
        printf "## %s (%.1f GiB)\n\n| variant | disk GiB | %% of source |", ds, logical[ds] / 2^30
        for (k = 1; k <= nw; k++) printf " GiB/s x%s |", wl[k]
        printf "\n|---|---:|---:|"
        for (k = 1; k <= nw; k++) printf "---:|"
        printf "\n| read from tmp | | |"
        speeds(ds, "read-tmp", "")
        printf "\n"
        row(ds, "none", "none", "")
        for (j = 1; j <= nl; j++) {
          if ((ds, "compress", ll[j], wl[1]) in cnt) row(ds, "compress zstd:" ll[j], "compress", ll[j])
          if ((ds, "compress-force", ll[j], wl[1]) in cnt) row(ds, "compress-force zstd:" ll[j], "compress-force", ll[j])
        }
        printf "\nDisk size is taken from the run with %s writer(s); speeds and sizes are means over %d run(s).\n\n", wl[1], cnt[ds, "none", "", wl[1]]
      }
    }' "$OUT_CSV"
}

if ((REPORT)); then
  report | tee "$OUT_MD"
  exit 0
fi

# Restored on exit: the compression option the filesystem is mounted with now (compress=no when it has none).
if [[ $DRY == 1 ]]; then
  ORIG="compress=zstd:-1"
else
  ORIG=$(findmnt -no OPTIONS "$MNT" | tr ',' '\n' | grep -E '^compress(-force)?(=|$)' | head -1 || true)
  ORIG="${ORIG:-compress=no}"
fi
echo "mount option to restore on exit: $ORIG"

sudo_keepalive_pid=""
restore() {
  [[ -n $sudo_keepalive_pid ]] && kill "$sudo_keepalive_pid" 2>/dev/null || true
  jobs -p | xargs -r kill 2>/dev/null || true
  if [[ $DRY != 1 ]]; then
    sudo mount -o "remount,$ORIG" "$MNT" || echo "RESTORE FAILED: run: sudo mount -o remount,$ORIG $MNT" >&2
  fi
  rm -rf "$DEST" "$RAM" "$RAM".*
}
trap restore EXIT
trap 'exit 130' INT TERM

if [[ $DRY != 1 ]]; then
  sudo -v
  while kill -0 "$$" 2>/dev/null; do sudo -n true; sleep 50; done >/dev/null &
  sudo_keepalive_pid=$!
fi

remount() {
  local opt=$1
  [[ $DRY == 1 ]] && return 0
  sudo mount -o "remount,$opt" "$MNT"
  local now
  now=$(findmnt -no OPTIONS "$MNT")
  case $opt in
    compress=no) [[ $now != *compress* ]] || { echo "remount to '$opt' did not stick: $now" >&2; exit 1; } ;;
    *) [[ ,$now, == *",$opt,"* ]] || { echo "remount to '$opt' did not stick: $now" >&2; exit 1; } ;;
  esac
}

disk_bytes() {
  if [[ $DRY == 1 ]]; then du -sb "$1" | cut -f1; else sudo compsize -b -x "$1" | awk '/^TOTAL/{print $3}'; fi
}

# shard <list with "size\tpath" lines> <N>: balanced split into $RAM.shard.K files of relative paths
shard() {
  rm -f "$RAM".shard.*
  sort -t$'\t' -k1,1nr "$1" | awk -F'\t' -v n="$2" -v pre="$RAM.shard." '
    { m = 1; for (k = 2; k <= n; k++) if (load[k] < load[m]) m = k
      load[m] += $1; print $2 > (pre m) }'
}

parallel_run() { # <command word: cp|cat> <N>
  local kind=$1 n=$2 k pids=()
  for ((k = 1; k <= n; k++)); do
    [[ -s $RAM.shard.$k ]] || continue
    if [[ $kind == cp ]]; then
      (cd "$RAM" && xargs -a "$RAM.shard.$k" -d '\n' cp --parents --reflink=never -t "$DEST") &
    else
      (cd "$RAM" && xargs -a "$RAM.shard.$k" -d '\n' cat >/dev/null) &
    fi
    pids+=($!)
  done
  local pid rc=0
  for pid in "${pids[@]}"; do wait "$pid" || rc=1; done
  return $rc
}

timed() { # prints elapsed seconds of "$@"; a ticker on stderr shows what is running
  local t0 t1 tick
  t0=$(date +%s.%N)
  local parent=$BASHPID
  (while kill -0 "$parent" 2>/dev/null; do
    printf '\r\033[K  running: %s  %ss' "$LABEL" "$(awk -v a="$t0" -v b="$(date +%s.%N)" 'BEGIN { printf "%.0f", b - a }')" >&2
    sleep 1
  done) >/dev/null &
  tick=$!
  local rc=0
  "$@" || rc=$?
  kill "$tick" 2>/dev/null || true
  wait "$tick" 2>/dev/null || true
  printf '\r\033[K' >&2
  t1=$(date +%s.%N)
  awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%.2f", b - a }'
  return $rc
}


START_TS=$(date +%s)
STEP=0
STEPS_TOTAL=0
LABEL=""
repeat() { local i; for ((i = 0; i < $2; i++)); do printf '%s' "$1"; done; }
fmt_dur() { printf '%dm%02ds' $(($1 / 60)) $(($1 % 60)); }
step_begin() { # <label>: overall bar on stderr, then the label is shown by the ticker
  LABEL=$1
  local width=30 done_n=$STEP now elapsed eta=0 filled
  STEP=$((STEP + 1))
  now=$(date +%s)
  elapsed=$((now - START_TS))
  ((done_n > 0)) && eta=$((elapsed * (STEPS_TOTAL - done_n) / done_n))
  filled=$((width * done_n / STEPS_TOTAL))
  printf '\r\033[K[%s%s] %d/%d  elapsed %s  ETA %s\n' \
    "$(repeat '#' "$filled")" "$(repeat '-' $((width - filled)))" \
    "$STEP" "$STEPS_TOTAL" "$(fmt_dur "$elapsed")" "$(fmt_dur "$eta")" >&2
}

STEPS_TOTAL=$(($(grep -c . <<<"$DATASETS") * ${#_w[@]} * (2 + ${#_m[@]} * ${#_l[@]}) * REPEATS))
echo "dataset,writers,mode,level,seconds,logical_bytes,disk_bytes" >"$OUT_CSV"
record() { # CSV row to the file, readable line to the terminal
  echo "$*" >>"$OUT_CSV"
  awk -F, '{
    mode = $3; if ($4 != "") mode = mode " zstd:" $4
    line = sprintf("  %-13s x%-2s %-24s %6.1f s  %5.2f GiB/s", $1, $2, mode, $5, $6 / $5 / 2^30)
    if ($7 != "") line = line sprintf("  -> %5.1f GiB on disk (%d%%)", $7 / 2^30, 100 * $7 / $6)
    print line }' <<<"$*"
}

write_run() { # <dataset> <writers> <mode> <level> <mount option or ->
  local ds=$1 n=$2 mode=$3 level=$4 opt=$5
  step_begin "$ds writers=$n write $mode ${level:+zstd:$level}"
  [[ $opt != - ]] && remount "$opt"
  rm -rf "$DEST"
  mkdir -p "$DEST"
  (cd "$RAM" && find . -type d -print0) | xargs -0 -I{} mkdir -p "$DEST/{}"
  sync
  [[ $DRY == 1 ]] || echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null
  local secs
  secs=$(timed bash -c 'parallel_run "$@" && sync' _ cp "$n")
  local got want
  got=$(find "$DEST" -type f | wc -l)
  want=$(wc -l <"$RAM.list")
  if ((got != want)); then
    echo "ERROR: $got files copied, expected $want" >&2
    exit 1
  fi
  record "$ds,$n,$mode,$level,$secs,$LOGICAL,$(disk_bytes "$DEST")"
}
export -f parallel_run
export RAM DEST

while IFS='|' read -r ds src cap; do
  [[ -n $ds ]] || continue
  echo "== dataset $ds: staging up to ${cap} GiB of '$src'"
  rm -rf "$RAM" "$RAM".*
  mkdir -p "$RAM"
  (cd "$src" && find . -type f -printf '%s\t%P\n') | sort -R --random-source=<(yes) |
    awk -F'\t' -v lim=$((cap * 1024 * 1024 * 1024)) '{ if (t + $1 > lim) next; t += $1; print }' >"$RAM.list"
  LOGICAL=$(awk -F'\t' '{ t += $1 } END { print t + 0 }' "$RAM.list")
  export LOGICAL
  avail=$(df --output=avail -B1 "$(dirname "$RAM")" | tail -1)
  if ((LOGICAL * 11 / 10 > avail)); then
    echo "not enough space in $(dirname "$RAM"): need $((LOGICAL / 1048576)) MiB, have $((avail / 1048576)) MiB" >&2
    exit 1
  fi
  cut -f2 "$RAM.list" | (cd "$src" && tar -cf - -T -) | tar -xf - -C "$RAM"
  echo "staged $((LOGICAL / 1048576)) MiB, $(wc -l <"$RAM.list") files"

  idx=0
  for n in $WRITERS; do
    shard "$RAM.list" "$n"
    for rep in $(seq "$REPEATS"); do
      echo "-- writers=$n run $rep/$REPEATS"
      step_begin "$ds writers=$n read from tmp"
      secs=$(timed parallel_run cat "$n")
      record "$ds,$n,read-tmp,,$secs,$LOGICAL,"
      remount "compress=no"
      write_run "$ds" "$n" none "" -
      for level in $LEVELS; do
        idx=$((idx + 1))
        modes=("${_m[@]}")
        # alternate the order between levels so neither mode always runs first
        if ((idx % 2 == 0 && ${#modes[@]} == 2)); then modes=("${modes[1]}" "${modes[0]}"); fi
        for mode in "${modes[@]}"; do
          write_run "$ds" "$n" "$mode" "$level" "$mode=zstd:$level"
        done
      done
    done
  done
done <<<"$DATASETS"

echo "== writing $OUT_MD"
report >"$OUT_MD"
echo "== done: $OUT_CSV, $OUT_MD"
cat "$OUT_MD"
