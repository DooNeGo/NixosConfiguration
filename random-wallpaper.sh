#!/usr/bin/env bash

WALL_DIR="$HOME/Wallpapers"
CONF_DIR="$HOME/.config/hypr"
CONF_FILE="$CONF_DIR/hyprpaper.conf"

RANDOM_WALL=$(find "$WALL_DIR" -type f | shuf -n 1)

mkdir -p "$CONF_DIR"
cat > "$CONF_FILE" <<EOF
preload = $RANDOM_WALL
wallpaper = ,$RANDOM_WALL
EOF

exec hyprpaper -c "$CONF_FILE"
