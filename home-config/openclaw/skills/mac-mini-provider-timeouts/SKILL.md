---
name: mac-mini-provider-timeouts
description: Mac-mini node — diagnose model/provider timeouts (agent slow to reply, model-fetch errors), test both OpenAI APIs, set correct api in config.
---

# Mac-mini provider timeout diagnosis

Trigger: user reports the mac agent answers slowly, or the log shows repeated
`[model-fetch] error ... model=<m> elapsedMs≈20000` (usually
"Activity recap timed out"). Known pattern: the model and key are healthy, but
the `responses` endpoint hangs while `chat/completions` works. OpenClaw defaults
to `api=openai-responses`, so every call hits the 20 s cap and falls back.

## Step 1 — read the log

`/tmp/openclaw/openclaw-<date>.log` — count
`[model-fetch] error` rows; note `provider=`, `api=`, `model=`, and whether
every failure sits at the same `elapsedMs` (the timeout ceiling — provider
never answers, not a slow network).

## Step 2 — rule out the channel

`curl -s -o /dev/null -w "%{http_code}
%{time_total}s\n" --max-time 25 https://api.openai.com/v1/models` from the
Mac. Fast (even a 401 without a key) means the network is fine. A slow
`/v1/models` (~10 s) with a valid key is normal for this route — not
proof of breakage on its own.

## Step 3 — locate the key without exposing it

It is not in `openclaw.json` plaintext; the path is in
`.secrets.providers.<name>.path` (for example `~/.secrets/openai-api-key`).
Read it into a shell variable on the Mac (`KEY=$(cat <path>)`); never
echo, paste, or transmit it.

## Step 4 — test both APIs manually

From the Mac, key in a variable:
- `POST /v1/chat/completions` with `"max_completion_tokens"` — NOT
  `max_tokens` (rejected 400 by newer models).
- `POST /v1/responses` with `"max_output_tokens": >=16` (below 16 is a
  400 `integer_below_min_value`), `--max-time` high enough to see a hang
  vs a fast error.

## Step 5 — decision rule

`chat/completions` returns 200 quickly while
`/v1/responses` hangs to the timeout → set the provider's
`"api": "openai-completions"` in `openclaw.json` (same model, hot reload
applies; ask the owner first — config edit). Both APIs hanging →
provider-side outage; both fast → suspect OpenClaw config elsewhere.

## Completion check

The failing api/model is identified from the log, both APIs verified
manually with masked keys, and the fix (or the provider-outage conclusion)
is stated with the timing evidence.
