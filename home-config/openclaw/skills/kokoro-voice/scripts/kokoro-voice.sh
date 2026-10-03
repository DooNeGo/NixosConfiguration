#!/usr/bin/env bash
# kokoro-voice helper: text (arg or stdin) -> opus ogg path on stdout.
# Exit codes mirror kokoro-ru-say: 2 args/empty, 3 missing data/voice, 4 ffmpeg/no audio.
set -euo pipefail
TEXT="${1:-}"
if [ -z "$TEXT" ]; then
  if [ -t 0 ]; then
    echo "usage: kokoro-voice.sh \"<text>\" (or pipe text on stdin)" >&2
    exit 2
  fi
  TEXT="$(cat)"
fi
[ -z "$TEXT" ] && { echo "empty text" >&2; exit 2; }
KOKORO="$(command -v kokoro-ru-say || ls -t /nix/store/*-kokoro-ru-1.0.0/bin/kokoro-ru-say | head -1)"
VOICE="${KOKORO_VOICE:-sveta}"
OUT="${KOKORO_OUT_DIR:-$PWD}/voice-$(date +%s%N)"
mkdir -p "$OUT"
printf '%s' "$TEXT" | "$KOKORO" -v "$VOICE" -o "$OUT/out.wav"
if FFERR="$(ffmpeg -y -i "$OUT/out.wav" -c:a libopus -b:a 48k -ar 48000 -ac 1 "$OUT/out.ogg" 2>&1)"; then
  :
else
  echo "ffmpeg failed: $(printf '%s\n' "$FFERR" | tail -1)" >&2
  exit 4
fi
[ -s "$OUT/out.ogg" ] || { echo "no audio produced" >&2; exit 4; }
echo "$OUT/out.ogg"
