#!/usr/bin/env bash
# kokoro-voice helper: text (arg or stdin) -> opus ogg path on stdout.
# Exit codes mirror kokoro-ru-say: 2 args/empty, 3 missing data/voice, 4 no audio.
set -euo pipefail
TEXT="${1:-}"
[ -z "$TEXT" ] && TEXT="$(cat)"
[ -z "$TEXT" ] && { echo "empty text" >&2; exit 2; }
KOKORO="$(command -v kokoro-ru-say || ls -t /nix/store/*-kokoro-ru-1.0.0/bin/kokoro-ru-say | head -1)"
VOICE="${KOKORO_VOICE:-sveta}"
OUT="${KOKORO_OUT_DIR:-$PWD}/voice-$(date +%s)"
mkdir -p "$OUT"
printf '%s' "$TEXT" | "$KOKORO" -v "$VOICE" -o "$OUT/out.wav"
ffmpeg -y -i "$OUT/out.wav" -c:a libopus -b:a 48k -ar 48000 -ac 1 "$OUT/out.ogg" 2>/dev/null
[ -s "$OUT/out.ogg" ] || { echo "no audio produced" >&2; exit 4; }
echo "$OUT/out.ogg"
