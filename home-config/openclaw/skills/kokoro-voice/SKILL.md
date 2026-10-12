---
name: "kokoro-voice"
description: "Russian voice note or spoken reply request: runs kokoro TTS, delivers a Telegram opus .ogg voice note."
metadata:
  openclaw:
    emoji: "🗣"
---

# kokoro-voice

Use for a spoken Russian reply sent as a Telegram voice note. Kokoro is the only
TTS engine; there is no fallback engine. The built-in `tts` tool has no runnable
provider in this setup: run the helper, then deliver with the message tool.

## 1. Generate the ogg

Run from the session workspace. Output lands in `$PWD` unless `KOKORO_OUT_DIR`
is set; `/tmp` is unmanaged and may be purged.

```
scripts/kokoro-voice.sh "<text>"
```

The script resolves the `kokoro-ru-say` binary, synthesizes wav, transcodes to
opus ogg, and prints the `.ogg` path on stdout.

- Env: `KOKORO_VOICE` (default `sveta`; also `masha`, `dima`), `KOKORO_OUT_DIR`.
- Long text: pipe it on stdin (`printf '%s' "$TEXT" | scripts/kokoro-voice.sh`) to avoid argument limits.
- Keep one call under ~1500 chars; summarize longer text first. Expect ~10x realtime plus ~4 s model load.
- Exit codes: 2 = bad args or empty text; 3 = missing data, checkpoint, or voice; 4 = ffmpeg failure or no audio.

Done when: exit 0 and the printed path exists and is non-empty.

## 2. Verify

`ffprobe` reports codec=opus in an ogg container. Note the duration.

## 3. Deliver

Primary, message tool:
`{action:"send", channel:"telegram", target:<chat>, media:"<abs path to out.ogg>", asVoice:true}`

Fallback, final reply only: a bare line `MEDIA:<abs path>` plus `[[audio_as_voice]]`, outside Markdown fences.

On failure, report the exit code and stderr. Do not switch to another engine.
