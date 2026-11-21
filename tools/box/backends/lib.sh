# shellcheck shell=bash
# The session runs as a real user (BOX_USER: the user of the home, else SESSION_USER of the system layer); the scripts
# run as the root of the system.

box_user() {
  local u=${BOX_USER:-$SESSION_USER} uid
  uid=$(id -u "$u")
  runuser -u "$u" -- env HOME="$(getent passwd "$u" | cut -d: -f6)" USER="$u" LOGNAME="$u" \
    XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" "$@"
}

# The user manager of the session user, and with it the bus that box_user needs, outlives the session unit.
box_session_up() {
  local u=${BOX_USER:-$SESSION_USER} uid
  uid=$(id -u "$u")
  loginctl enable-linger "$u"
  for _ in $(seq 30); do
    [ -S "/run/user/$uid/bus" ] && return 0
    sleep 1
  done
  echo "the user manager of $u has no bus after 30 s" >&2
  return 1
}
