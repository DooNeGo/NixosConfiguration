# shellcheck shell=bash
# requires: session (shared)
# The compositor of the session draws: within 60 s a frame has a pixel deviation of 6 or more (a flat frame is below).
sd=0
for _ in $(seq 30); do
  sd=$(box_shot 1 0 | awk '{ print $3 }') || sd=0
  if awk -v s="$sd" 'BEGIN { exit !(s >= 6) }'; then
    echo "frame deviation $sd"
    exit 0
  fi
  sleep 2
done
echo "the frames stay flat (deviation $sd) for 60 s" >&2
exit 1
