# shellcheck shell=bash
# requires: desktop-ready
uid=$(box_user id -u)
dropin=/run/user/$uid/systemd/user/hyprlock-initial.service.d
cleanup() {
  rm -f "$dropin/box-failure.conf"
  box_user systemctl --user daemon-reload
  box_user systemctl --user reset-failed hyprlock-initial.service sunshine.service || true
}
trap cleanup EXIT
box_user systemctl --user stop sunshine.service hyprlock-initial.service
mkdir -p "$dropin"
cat > "$dropin/box-failure.conf" <<'EOF'
[Service]
ExecStartPre=
ExecStartPre=/run/current-system/sw/bin/false
Restart=no
EOF
box_user systemctl --user daemon-reload
if box_user systemctl --user start sunshine.service; then
  echo "Sunshine started despite a failed lock" >&2
  exit 1
fi
if box_user systemctl --user is-active --quiet sunshine.service; then
  echo "Sunshine is active despite a failed lock" >&2
  exit 1
fi
echo "Sunshine was blocked when the lock failed"

cat > "$dropin/box-failure.conf" <<'EOF'
[Service]
ExecStartPre=
ExecStart=
ExecStart=/run/current-system/sw/bin/sleep 30
ExecStartPost=
TimeoutStartSec=2
Restart=no
EOF
box_user systemctl --user daemon-reload
box_user systemctl --user reset-failed hyprlock-initial.service sunshine.service
if box_user systemctl --user start sunshine.service; then
  echo "Sunshine started without lock readiness" >&2
  exit 1
fi
echo "Sunshine was blocked while lock readiness was missing"

marker=/run/user/$uid/box-lock-failed-once
rm -f "$marker"
cat > "$dropin/box-failure.conf" <<EOF
[Service]
ExecStartPre=
ExecStartPre=/run/current-system/sw/bin/sh -c 'test -e $marker || { touch $marker; exit 1; }'
RestartSec=1
EOF
box_user systemctl --user daemon-reload
box_user systemctl --user reset-failed hyprlock-initial.service sunshine.service
box_user systemctl --user start --no-block sunshine.service
for _ in $(seq 30); do
  box_user systemctl --user is-active --quiet sunshine.service && break
  sleep 1
done
box_user systemctl --user is-active --quiet sunshine.service || { echo "Sunshine did not recover after lock retry" >&2; exit 1; }
rm -f "$marker"
echo "Sunshine started after the lock recovered"
