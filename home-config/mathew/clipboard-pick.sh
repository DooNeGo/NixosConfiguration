#!/usr/bin/env bash
# Pick an entry of the clipboard history, make it the clipboard and paste it into the focused window.
# Images are listed with a thumbnail. Terminals paste with CTRL+SHIFT+V, everything else with CTRL+V.
cache=${XDG_CACHE_HOME:-$HOME/.cache}/clipboard-pick
mkdir -p "$cache"
find "$cache" -name '*.png' -mtime +7 -delete

mapfile -t lines < <(cliphist list)
[ "${#lines[@]}" -gt 0 ] || exit 0

# One row per entry: "label", or "label\0icon\x1f<thumbnail>" for an image (rofi dmenu row options).
# Thumbnails are made before rofi opens, so only the newest ones get one.
max_thumbs=30
# Writes the thumbnail through a temporary name, so a failed run leaves no partial file that would be reused.
make_thumb() {
    [ -s "$2" ] && return 0
    if printf '%s\n' "$1" | cliphist decode | magick - -thumbnail 256x256^ -gravity center -extent 256x256 "$2.$$.tmp.png"; then
        mv -f "$2.$$.tmp.png" "$2"
    else
        rm -f "$2.$$.tmp.png"
        return 1
    fi
}

rows() {
    local line id preview thumb label count=0
    for line in "${lines[@]}"; do
        id=${line%%$'\t'*}
        preview=${line#*$'\t'}
        if [[ $preview =~ ^\[\[\ binary\ data\ (.*)\ (png|jpg|jpeg|bmp|gif|webp)\ ([0-9]+x[0-9]+)\ \]\]$ ]]; then
            label="Изображение ${BASH_REMATCH[3]}, ${BASH_REMATCH[1]}"
            # Size and dimensions in the name: cliphist ids restart after a wiped database.
            thumb=$cache/thumb-$id-${BASH_REMATCH[3]}-${BASH_REMATCH[1]// /}.png
            count=$((count + 1))
            if [ "$count" -le "$max_thumbs" ] && make_thumb "$line" "$thumb"; then
                printf '%s\0icon\x1f%s\n' "$label" "$thumb"
            else
                printf '%s\n' "$label"
            fi
        else
            # An empty row would shift the indexes rofi returns.
            [[ $preview =~ [^[:space:]] ]] || preview="(пусто)"
            printf '%s\n' "$preview"
        fi
    done
}

# The icon sits right of the text, so text entries show no gap on the left.
theme='element { children: [ element-text, element-icon ]; }'
index=$(rows | rofi -dmenu -i -format i -p "󰅍" -theme-str "$theme") || exit 0
[ -n "$index" ] || exit 0
printf '%s\n' "${lines[index]}" | cliphist decode | wl-copy

# rofi has to give the focus back to the window that was active before it.
sleep 0.2
# No focused window or no hyprctl answer: paste as for a regular window.
class=$(hyprctl activewindow -j 2>/dev/null | jq -r '.class // ""' 2>/dev/null) || class=""
case "$class" in
kitty | *[Tt]erminal* | Alacritty | foot) wtype -M ctrl -M shift -k v -m shift -m ctrl ;;
*) wtype -M ctrl -k v -m ctrl ;;
esac
