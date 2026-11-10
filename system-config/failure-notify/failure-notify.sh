#!/usr/bin/env bash
# Built by system-config/failure-notify.nix, which sets FAILURE_NOTIFY_STATE_DIR, FAILURE_NOTIFY_RENOTIFY_SEC
# (seconds) and FAILURE_NOTIFY_SINKS (one executable per line); FAILURE_NOTIFY_DIR overrides the directory.
#
# One file per open problem: first seen, expiry (0 = never), last sink call, message; one value per line.
# A repeated report of the same id keeps "first seen", so shells show an incident once, and calls the sinks again
# only after FAILURE_NOTIFY_RENOTIFY_SEC, so a unit that fails every 10 minutes does not flood them.

set -euo pipefail
: "${FAILURE_NOTIFY_STATE_DIR:?set by system-config/failure-notify.nix}"
: "${FAILURE_NOTIFY_RENOTIFY_SEC:?set by system-config/failure-notify.nix}"
: "${FAILURE_NOTIFY_SINKS=}"

dir=${FAILURE_NOTIFY_DIR:-$FAILURE_NOTIFY_STATE_DIR}
sinks=()
while IFS= read -r sink; do
  if [[ -n $sink ]]; then sinks+=("$sink"); fi
done <<<"$FAILURE_NOTIFY_SINKS"

help() {
  # Unquoted on purpose: it expands the two variables named in the text. Write any other dollar sign in the text as \$.
  cat <<EOF
Usage: failure-notify report [--ttl SECONDS] [--] ID MESSAGE...
       failure-notify clear ID
       failure-notify list
       failure-notify -h | --help

Keep a record of a failure that shells and desktop sessions then show to the users.

Commands:
  report   Create or renew the record ID. A repeated report keeps the time of the first one and calls the
           sinks again only after $FAILURE_NOTIFY_RENOTIFY_SEC seconds. Needs write access to the record directory.
  clear    Remove the record ID. Needs write access to the record directory.
  list     Print the open records, one per line: time, ID, message.

Options:
  --ttl SECONDS  Drop the record after SECONDS (default: keep it until it is cleared).
  -h, --help     Show this help and exit.

Environment:
  FAILURE_NOTIFY_DIR  Record directory (default: $FAILURE_NOTIFY_STATE_DIR).

Exit status: 0 on success, 1 on a runtime error (e.g. the directory cannot be locked), 2 on a usage error.

Examples:
  failure-notify report backup-disk "backup disk is not connected"
  failure-notify report --ttl 3600 smartd-sda "SMART: reallocated sectors"
  failure-notify clear backup-disk
EOF
}
usage() {
  [[ $# -eq 0 ]] || echo "failure-notify: $*" >&2
  echo "Try 'failure-notify --help' for more information." >&2
  exit 2
}
is_help() { [[ ${1:-} == -h || ${1:-} == --help ]]; }
# A leading dot would hide the record from the globs, ".." would escape the directory.
sanitize() {
  local id
  id=$(printf '%s' "$1" | tr -c 'A-Za-z0-9_.@:-' '_')
  [[ -n $id ]] || usage
  printf '%s' "${id/#./_}"
}
# Only the changes of the directory are serialised, so that a pruning cannot delete a record that a report has
# just renewed. Fails quietly when the lock file cannot be opened (list as an ordinary user).
lock() {
  { exec 9>"$dir/.lock"; } 2>/dev/null && flock -w 30 9
}
# The usual cause is no write access (the directory is root's), not a timeout.
lock_failed() {
  if [[ -w $dir ]]; then
    echo "failure-notify: timed out waiting for the lock on $dir" >&2
  else
    echo "failure-notify: no write access to $dir (run it as root, e.g. with sudo)" >&2
  fi
  exit 1
}
unlock() {
  flock -u 9
}
prune() {
  local f expires now
  now=$(date +%s)
  for f in "$dir"/*; do
    [[ -f $f ]] || continue
    { read -r _ && read -r expires; } <"$f" || continue
    if ((expires != 0 && expires <= now)); then
      lock || return 0
      # The record may have been renewed while waiting for the lock.
      { read -r _ && read -r expires; } <"$f" && ((expires != 0 && expires <= now)) && rm -f "$f"
      unlock
    fi
  done
}

cmd=${1:-}
[[ $# -gt 0 ]] && shift
case $cmd in
  report)
    ttl=0
    while [[ ${1:-} == -* ]]; do
      case $1 in
        -h | --help)
          help
          exit 0
          ;;
        --ttl)
          [[ $# -ge 2 ]] || usage "option '--ttl' requires an argument"
          ttl=$2
          shift 2
          ;;
        --ttl=*)
          ttl=${1#--ttl=}
          shift
          ;;
        --)
          shift
          break
          ;;
        *) usage "unknown option '$1'" ;;
      esac
    done
    [[ $ttl =~ ^[0-9]+$ ]] || usage "--ttl needs a number of seconds, got '$ttl'"
    [[ $# -ge 2 ]] || usage "report needs an ID and a message"
    id=$(sanitize "$1")
    shift
    # Shown raw in terminals: no control characters.
    message=$(printf '%s' "$*" | tr '\n\t' '  ' | tr -d '\000-\037\177')
    prune
    now=$(date +%s)
    since=$now
    notified=0
    if [[ -f $dir/$id ]]; then
      { read -r since && read -r _ && read -r notified; } <"$dir/$id" || true
    fi
    expires=0
    if ((ttl > 0)); then expires=$((now + ttl)); fi
    notify=0
    if ((now - notified >= FAILURE_NOTIFY_RENOTIFY_SEC)); then
      notify=1
      notified=$now
    fi
    lock || lock_failed
    printf '%s\n%s\n%s\n%s\n' "$since" "$expires" "$notified" "$message" >"$dir/.tmp.$$"
    chmod 644 "$dir/.tmp.$$"
    mv "$dir/.tmp.$$" "$dir/$id"
    unlock
    if ((notify)); then
      for sink in "${sinks[@]}"; do
        FAILED_UNIT=$id FAILED_MESSAGE=$message FAILED_TIME=$since timeout 10 "$sink" ||
          echo "failure-notify: sink $sink failed" >&2
      done
    fi
    ;;
  clear)
    if is_help "$@"; then
      help
      exit 0
    fi
    [[ $# -eq 1 ]] || usage "clear needs exactly one ID"
    id=$(sanitize "$1")
    lock || lock_failed
    rm -f "$dir/$id"
    ;;
  list)
    if is_help "$@"; then
      help
      exit 0
    fi
    [[ $# -eq 0 ]] || usage "list takes no arguments"
    prune 2>/dev/null || true
    for f in "$dir"/*; do
      [[ -f $f ]] || continue
      { read -r since && read -r _ && read -r _ && IFS= read -r message; } <"$f" || continue
      printf '%s  %s  %s\n' "$(date -d "@$since" '+%F %R')" "${f##*/}" "$message"
    done
    ;;
  -h | --help)
    help
    ;;
  "") usage "missing command" ;;
  *) usage "unknown command '$cmd'" ;;
esac
