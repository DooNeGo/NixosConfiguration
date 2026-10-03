---
name: "kokoro-voice"
description: "Voice replies via local kokoro-ru TTS (Russian, Telegram)."
metadata:
  openclaw:
    emoji: "🗣"
---

# kokoro-voice

Use when the user needs a spoken (voice-note) Russian reply. Kokoro is the
only TTS engine (piper fallback removed by decision). The built-in `tts`
tool has no runnable provider in this setup — run the CLI yourself and
deliver via the message tool.

## 1. Resolve binary

`kokoro-ru-say` is normally on PATH (pkgs.kokoro-ru in home.packages). If
not found, fall back to the store glob:

```
KOKORO="$(command -v kokoro-ru-say || ls -t /nix/store/*-kokoro-ru-1.0.0/bin/kokoro-ru-say | head -1)"
```

The wrapper self-exports `KOKORO_RU_DATA` — no env setup needed.

## 2. Choose voice / rate

- `-v sveta|masha|dima` (default `sveta`).
- `-r RATE` (>1 = faster); `-c` is a checkpoint path, NOT cpu count.

## 3. Generate wav in the session workspace (never /tmp)

```
OUT="$PWD/voice-$(date +%s)"; mkdir -p "$OUT"
printf '%s' "$TEXT" | "$KOKORO" -v sveta -o "$OUT/out.wav"
```

stdin avoids shell-argument limits on long text. Exit codes: 2 = bad
args/empty text, 3 = missing data/checkpoint/voice, 4 = no audio produced.
Keep one call under ~1500 chars (longer: summarize first); ~10x realtime
plus ~4 s model load.

## 4. Transcode for Telegram voice note

```
ffmpeg -y -i "$OUT/out.wav" -c:a libopus -b:a 48k -ar 48000 -ac 1 "$OUT/out.ogg"
```

## 5. Deliver

Primary — message tool:
`{action:"send", channel:"telegram", target:<chat>, media:"<abs path to out.ogg>", asVoice:true}`

Fallback (final reply only): a bare line `MEDIA:<abs path>` plus
`[[audio_as_voice]]`, outside Markdown fences.

## 6. Verify

Non-empty `.ogg` (ffprobe duration); report path + duration. On failure,
report the exit code and stderr — no fallback engine.
