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
Done when: the resolved path is an existing executable.

## 2. Choose voice / rate

- `-v sveta|masha|dima` (default `sveta`).
- `-r RATE` (>1 = faster); `-c` is a checkpoint path, NOT cpu count.
Done when: a voice (and rate, if overriding) is picked — defaults are fine.

## 3. Generate wav in the session workspace (write outbound media under
the workspace: /tmp works today but is unmanaged and may be purged)

Preferred when available — the bundled helper does steps 3+4 in one go and
prints the final .ogg path directly:

```
scripts/kokoro-voice.sh "<text>"
```
(env `KOKORO_VOICE` / `KOKORO_OUT_DIR` override voice / output dir). The
manual steps below stay as the explicit path.

```
OUT="$PWD/voice-$(date +%s)"; mkdir -p "$OUT"
printf '%s' "$TEXT" | "$KOKORO" -v sveta -o "$OUT/out.wav"
```

stdin avoids shell-argument limits on long text. Exit codes: 2 = bad
args/empty text, 3 = missing data/checkpoint/voice, 4 = no audio produced.
Keep one call under ~1500 chars (longer: summarize first); ~10x realtime
plus ~4 s model load.
Done when: the wav exists and is non-empty.

## 4. Transcode for Telegram voice note

```
ffmpeg -y -i "$OUT/out.wav" -c:a libopus -b:a 48k -ar 48000 -ac 1 "$OUT/out.ogg"
```

Done when: ffprobe reports codec=opus in an ogg container.

## 5. Deliver

Primary — message tool:
`{action:"send", channel:"telegram", target:<chat>, media:"<abs path to out.ogg>", asVoice:true}`

Fallback (final reply only): a bare line `MEDIA:<abs path>` plus
`[[audio_as_voice]]`, outside Markdown fences.

## 6. Verify

Non-empty `.ogg` (ffprobe duration); report path + duration. On failure,
report the exit code and stderr — no fallback engine.
