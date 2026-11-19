#!/usr/bin/env bash
# Run the Home Manager configuration of any user in a NixOS container (rootless podman, no sudo) with the host GPU and
# the host nix store, and look at its desktop session: the test target of docs/box.md.
set -euo pipefail

prog=${0##*/}
repo=$(cd "$(dirname "$0")/.." && pwd)
state=${XDG_STATE_HOME:-$HOME/.local/state}/box
name=box
session=hyprland-headless-root

usage() {
  cat << EOF
Usage: $prog COMMAND

Commands:
  up                          build the container system, (re)create the container, wait until systemd inside is up
  down                        stop the container and remove its root
  status                      print the state of the container and of the session unit
  switch TARGET
                              build homeConfigurations.TARGET (a Linux target of home-config/) for the container
                              root and activate it inside
  session [start|stop|restart]
                              control the Hyprland session in the container (default: restart); start and restart wait
                              until Hyprland has an output
  shot [COUNT [DELAY]]        grim frames of HEADLESS-1 into $state/shots (replacing the previous ones), with the pixel
                              standard deviation
  exec COMMAND [ARG]...       run a command in the container as its root (a single argument is a shell command line)

The container has no network. Its home and /tmp are lost with the container: run switch after every up.
EOF
}

usage_error() {
  echo "$prog: $1" >&2
  echo "Try '$prog --help' for more information." >&2
  exit 2
}

# The inner shell of exec and switch gets the environment of the container root's user session.
inner_env=(
  USER=root HOME=/root
  XDG_RUNTIME_DIR=/run/user/0
  DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/0/bus
  NIX_REMOTE=daemon
)

# Everything the commands take is checked here, before anything is built or started.
check_args() {
  local cmd=$1
  shift
  case $cmd in
    up | down | status) [ $# -eq 0 ] || usage_error "$cmd takes no arguments" ;;
    switch)
      [ $# -eq 1 ] || usage_error "switch needs exactly one TARGET"
      [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || usage_error "invalid TARGET '$1'"
      [ -f "$repo/home-config/$1/flake.nix" ] || usage_error "no flake home-config/$1"
      ;;
    session)
      [ $# -le 1 ] || usage_error "session takes one action"
      [[ ${1:-restart} =~ ^(start|stop|restart)$ ]] || usage_error "session: start, stop or restart"
      ;;
    shot)
      [ $# -le 2 ] || usage_error "shot takes COUNT and DELAY"
      [[ ${1:-1} =~ ^[0-9]+$ ]] && [ "${1:-1}" -ge 1 ] || usage_error "COUNT must be a positive integer"
      [[ ${2:-0.3} =~ ^[0-9]+(\.[0-9]+)?$ ]] || usage_error "DELAY must be a number of seconds"
      ;;
    exec) [ $# -ge 1 ] || usage_error "exec needs a command" ;;
  esac
}

# A temp file in the same directory, then rename: a parallel invocation never reads half a file.
write_conf() {
  cat > "$1.tmp.$$"
  mv -f "$1.tmp.$$" "$1"
}

setup_podman() {
  local podman_env
  mkdir -p "$state/roots"
  # An out link per build is a GC root: the running container uses these store paths.
  podman_env=$(nix build --out-link "$state/roots/podman" --print-out-paths "$repo/system-config/box#packages.x86_64-linux.podman")
  # vfs: overlay needs privileges a rootless user does not have, and the container is started from a rootfs directory.
  write_conf "$state/storage.conf" << EOF
[storage]
driver = "vfs"
graphroot = "$state/storage"
runroot = "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/$name"
EOF
  # newuidmap and newgidmap are the setuid wrappers of the host.
  export PATH="$podman_env/bin:/run/wrappers/bin:$PATH"
  export CONTAINERS_STORAGE_CONF=$state/storage.conf
}

running() {
  podman container exists "$name" 2> /dev/null && [ "$(podman inspect -f '{{.State.Running}}' "$name")" = true ]
}

require_running() {
  running || {
    echo "$prog: the container is not running; start it with '$prog up'" >&2
    exit 1
  }
}

# The session runs on the same GPU as the owner's: not next to it.
refuse_while_stream() {
  if systemctl is-active --quiet hyprland-headless-mathew.service steam-bigpicture-mathew.service; then
    echo "$prog: mathew's stream or Steam session is running; stop it first" >&2
    exit 1
  fi
}

# exec sets this to (-i) so that its stdin reaches the command.
stdin_flag=()

inner() {
  local args=("${stdin_flag[@]}") v
  for v in "${inner_env[@]}"; do args+=(-e "$v"); done
  podman exec "${args[@]}" "$name" /run/current-system/sw/bin/bash -lc "$1"
}

remove_container() {
  # SIGTERM to `podman run` reaches systemd inside as a signal it ignores: the unit would wait for its 90 s stop
  # timeout. `podman stop` sends the stop signal of systemd containers, SIGRTMIN+3, which powers it off.
  podman stop -t 10 "$name" > /dev/null 2>&1 || true
  systemctl --user stop "$name.service" 2> /dev/null || true
  podman rm -f "$name" > /dev/null 2>&1 || true
}

# A user manager that started before openclaw-npm joined `video` lacks the group and Hyprland would fail with an
# unhelpful "CBackend::create() failed".
require_video() {
  local gid pid
  gid=$(getent group video | cut -d: -f3)
  pid=$(pgrep -u "$(id -u)" -x systemd | head -1)
  grep -qE "^Groups:.*[[:space:]]$gid([[:space:]]|$)" "/proc/$pid/status" || {
    echo "$prog: the user manager of $(id -un) has no group video; the owner restarts it (systemctl restart user@$(id -u).service)" >&2
    exit 1
  }
}

# up and down remove the container and its root: one at a time.
take_lock() {
  exec 9> "$state/lock"
  flock -n 9 || {
    echo "$prog: another up or down is running" >&2
    exit 1
  }
}

cmd_up() {
  take_lock
  require_video
  refuse_while_stream
  local top
  top=$(nix build --out-link "$state/roots/top" --print-out-paths "$repo/system-config/box#nixosConfigurations.box.config.system.build.toplevel")
  remove_container
  systemctl --user reset-failed "$name.service" 2> /dev/null || true
  # Files of container users belong to subuids: only the user namespace of podman may remove them.
  podman unshare rm -rf "$state/rootfs"
  mkdir -p "$state/rootfs" "$state/shots"

  # keep-groups: the host group `video` gives /dev/dri/card0, which Hyprland needs even with only a headless output
  # (renderD128 alone is not enough). The daemon socket is for the nix commands of the Home Manager activation.
  # The nvidia-uvm and modeset nodes exist only after the driver has created them.
  local devices=() d
  for d in /dev/dri/card0 /dev/dri/renderD128 /dev/nvidiactl /dev/nvidia0 /dev/nvidia-modeset /dev/nvidia-uvm /dev/nvidia-uvm-tools; do
    [ -e "$d" ] && devices+=(--device "$d")
  done
  systemd-run --user --quiet --unit="$name" \
    --setenv=PATH --setenv=CONTAINERS_STORAGE_CONF \
    podman run --rm --name "$name" --rootfs --network=none \
    --systemd=always --group-add keep-groups \
    -v /nix/store:/nix/store:ro -v /nix/var/nix/daemon-socket:/nix/var/nix/daemon-socket \
    -v /run/opengl-driver:/run/opengl-driver:ro -v "$state/shots:/shots" \
    "${devices[@]}" \
    --tmpfs /run/wrappers:rw,exec,suid,mode=755 \
    "$state/rootfs" "$top/init"

  local i state_now
  for i in $(seq 60); do
    if running; then
      state_now=$(inner 'systemctl is-system-running' 2> /dev/null || true)
      [[ $state_now =~ ^(running|degraded)$ ]] && break
    fi
    # No --collect: the unit of a failed podman run stays and its journal says why.
    if ! systemctl --user is-active --quiet "$name.service"; then
      journalctl --user -u "$name.service" --no-pager -n 15 >&2
      echo "$prog: podman run exited" >&2
      remove_container
      exit 1
    fi
    if [ "$i" -eq 60 ]; then
      echo "$prog: systemd in the container did not come up in 120 s" >&2
      remove_container
      exit 1
    fi
    sleep 2
  done
  echo "$prog: the container is up ($state_now)"
  if [ "$state_now" = degraded ]; then
    inner 'systemctl --failed --no-legend' >&2 || true
  fi
}

cmd_down() {
  take_lock
  remove_container
  podman unshare rm -rf "$state/rootfs"
}

cmd_status() {
  if running; then
    echo "container: running, systemd $(inner 'systemctl is-system-running' || true)"
    echo "session: $(inner "systemctl is-active $session" || true)"
  else
    echo "container: not running"
  fi
}

cmd_switch() {
  local target=$1 out
  require_running
  refuse_while_stream

  export BOX_FLAKE="git+file://$repo?dir=home-config/$target" BOX_TARGET=$target
  # The target flake and its lock are used as they are; only the user and the home directory change.
  # shellcheck disable=SC2016
  out=$(nix build --impure --out-link "$state/roots/home-$target" --print-out-paths --expr '
    let
      flake = builtins.getFlake (builtins.getEnv "BOX_FLAKE");
      config = flake.homeConfigurations.${builtins.getEnv "BOX_TARGET"};
    in
    assert config.pkgs.stdenv.hostPlatform.isLinux || throw "TARGET is not a Linux configuration";
    (config.extendModules {
      modules = [
        (
          { lib, ... }:
          {
            home.username = lib.mkForce "root";
            home.homeDirectory = lib.mkForce "/root";
          }
        )
      ];
    }).activationPackage
  ')
  echo "$out"
  # A file Hyprland wrote on its first start (hypr/hyprland.lua) would block the activation: keep it as .bak.
  inner "HOME_MANAGER_BACKUP_EXT=bak HOME_MANAGER_BACKUP_OVERWRITE=1 $out/activate"
}

cmd_session() {
  local action=${1:-restart}
  require_running
  [ "$action" = stop ] || refuse_while_stream
  inner "systemctl $action $session"
  [ "$action" = stop ] && return 0
  # shellcheck disable=SC2016
  inner 'for i in $(seq 120); do
      sig=$(hyprctl instances -j 2>/dev/null | jq -r ".[-1].instance // empty" 2>/dev/null)
      [ -n "$sig" ] && HYPRLAND_INSTANCE_SIGNATURE=$sig hyprctl monitors -j 2>/dev/null | jq -e "length > 0" >/dev/null && exit 0
      sleep 0.5
    done
    echo "no Hyprland output appears in 60 s" >&2; exit 1'
}

cmd_shot() {
  local count=${1:-1} delay=${2:-0.3}
  require_running
  rm -f "$state"/shots/*.ppm
  # Without errexit a failed grim would still end with exit status 0.
  # shellcheck disable=SC2016
  inner "set -eo pipefail
    sig=\$(hyprctl instances -j 2>/dev/null | jq -r '.[-1].instance // empty' 2>/dev/null || true)
    [ -n \"\$sig\" ] || { echo 'no Hyprland instance' >&2; exit 1; }
    export HYPRLAND_INSTANCE_SIGNATURE=\$sig
    display=\$(ls /run/user/0 | grep '^wayland-[0-9]\$' | head -1 || true)
    [ -n \"\$display\" ] || { echo 'no Wayland socket' >&2; exit 1; }
    export WAYLAND_DISPLAY=\$display
    for i in \$(seq $count); do
      f=/shots/\$(printf %02d \$i).ppm
      grim -t ppm -o HEADLESS-1 \$f
      echo \"\$f stddev \$(magick \$f -format '%[fx:standard_deviation*255]' info:)\"
      sleep $delay
    done"
}

cmd_exec() {
  require_running
  stdin_flag=(-i)
  if [ $# -eq 1 ]; then inner "$1"; else inner "$(printf '%q ' "$@")"; fi
}

[ $# -ge 1 ] || usage_error "COMMAND is required"
cmd=$1
shift
case $cmd in
  -h | --help)
    usage
    exit 0
    ;;
  up | down | status | switch | session | shot | exec) ;;
  -*) usage_error "unknown option '$cmd'" ;;
  *) usage_error "unknown command '$cmd'" ;;
esac
# The arguments of exec belong to the command it runs.
if [ "$cmd" != exec ]; then
  for arg in "$@"; do
    if [ "$arg" = -h ] || [ "$arg" = --help ]; then
      usage
      exit 0
    fi
  done
fi
check_args "$cmd" "$@"

setup_podman
"cmd_$cmd" "$@"
