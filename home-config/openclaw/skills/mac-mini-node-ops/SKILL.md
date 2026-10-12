---
name: "mac-mini-node-ops"
description: "Remote OpenClaw administration on the Mac-mini node — plugin installs, config edits, gateway stop/start, provider timeouts; \"on the Mac-mini…\" tasks."
---

# Mac-mini node operations

Trigger: tasks on the Mac-mini (mac agent config, plugins, lossless, batch
operations). Access: `ssh -o BatchMode=yes worker@100.94.123.27` (Tailscale);
CLI is `/opt/homebrew/bin/openclaw`.

## Rules (order matters)

1. **Backup first**: `cp ~/.openclaw/openclaw.json
   ~/openclaw-backup-<date>/openclaw.json.pre-<task>-$(date +%H%M)` before any
   change. An existing set `~/openclaw-backup-20261006/` also holds agent DBs.
2. **Check gateway state**: `launchctl list | grep openclaw` (empty = stopped).
   The owner usually runs the mac gateway STOPPED.
3. **Plugin semantics**: `openclaw plugins install` hot-applies only when a
   Gateway is running; with no Gateway it is saved for next start. Therefore
   install the managed plugin FIRST, then remove `load.paths` — the reverse
   order leaves `entries.<plugin>` enabled with no source →
   `configured-unavailable` (docs `tools/plugin.md:331-334`).
4. **Apply config**: if a Gateway IS running, `openclaw plugins reload <plugin>`
   applies edits (restart only if it reports `restartRequired`). Start with
   `openclaw gateway start` or
   `launchctl load ~/Library/LaunchAgents/ai.openclaw.gateway.plist`.
5. **Log incrementally** to `research/mac-batch-c/LOG.md` (never /tmp — it
   gets wiped).

## Inventory / verification

- `openclaw plugins list --enabled --json` after changes
- `openclaw plugins inspect <id>` for a single plugin
- Final check for stopped-gateway changes: `launchctl list | grep openclaw`
  still empty + config JSON valid (`python3 -m json.tool ~/.openclaw/openclaw.json`).

Policy context: mac-mini is a wide-spectrum general-purpose agent (owner
decision 2026-10-06) — do not mass-disable plugins on usage evidence; disable
only providers without keys or true duplicates.

## Model-provider timeouts (agent slow to reply)

Trigger: user reports the mac agent answers slowly, or the log shows repeated
`[model-fetch] error ... model=<m> elapsedMs≈20000` (usually
`"Activity recap timed out"`). Verified 2026-10-07: the model and key were
healthy; the `responses` endpoint hung while `chat/completions` worked —
OpenClaw defaults to `api=openai-responses`, so every call hit the 20 s cap
and fell back.

1. **Read the log**: `/tmp/openclaw/openclaw-<date>.log` — count
   `[model-fetch] error` rows; note `provider=`, `api=`, `model=`, and whether
   every failure sits at the same `elapsedMs` (the timeout ceiling — provider
   never answers, not a slow network).
2. **Rule out the channel**: `curl -s -o /dev/null -w "%{http_code}
%{time_total}s\n" --max-time 25 https://api.openai.com/v1/models` from the
   Mac. Fast (even a 401 without a key) means the network is fine. A slow
   `/v1/models` (~10 s) with a valid key is normal for this route — not
   proof of breakage on its own.
3. **Locate the key without exposing it**: it is not in
   `openclaw.json` plaintext; the path is in
   `.secrets.providers.<name>.path` (2026-10-07: `~/.secrets/openai-api-key`).
   Read it into a shell variable on the Mac (`KEY=$(cat <path>)`); never
   echo, paste, or transmit it.
4. **Test both APIs manually** (from the Mac, key in a variable):
   - `POST /v1/chat/completions` with `"max_completion_tokens"` — NOT
     `max_tokens` (rejected 400 by newer models).
   - `POST /v1/responses` with `"max_output_tokens": >=16` (below 16 is a
     400 `integer_below_min_value`), `--max-time` high enough to see a hang
     vs a fast error.
5. **Decision rule**: `chat/completions` returns 200 quickly while
   `/v1/responses` hangs to the timeout → set the provider's
   `"api": "openai-completions"` in `openclaw.json` (same model, hot reload
   applies; ask the owner first — config edit). Both APIs hanging →
   provider-side outage; both fast → suspect OpenClaw config elsewhere.

Completion check: the failing api/model is identified from the log, both APIs
verified manually with masked keys, and the fix (or the provider-outage
conclusion) is stated with the timing evidence.

## Google account auth on the Mac (gog) — invalid_client recovery

Trigger: `gog auth add <email>` fails at the code exchange with
`invalid_client` while the browser consent flow itself works. Verified
2026-10-08: the auth URL and consent are fine; the OAuth client secret in the
gog keyring was stale/rejected. gog reads the secret from the KEYRING —
replacing `~/.config/gogcli/client_secret.json` alone changes nothing.

1. **Probe the client creds without exposing the secret.** Read the secret
   into a shell var and length-check it (`echo ${#SEC}`) — never a
   placeholder; then `POST https://oauth2.googleapis.com/token` with
   client_id, `client_secret=$SEC`, `code=probe-dummy`,
   `grant_type=authorization_code`, `redirect_uri=http://localhost`.
   `invalid_grant — Malformed auth code` = client ACCEPTED (a code-side
   failure; secret is fine). `invalid_client` = secret rejected. Both outputs
   verified 2026-10-08.
   Pitfall (cost a false "stale secret" diagnosis, withdrawn same day): a
   probe curl written with a literal `***` instead of the interpolated
   variable tested garbage and "proved" a healthy secret bad. Interpolate and
   length-check every time.
2. **Import a fresh secret.** User exports `client_secret.json` for the same
   client_id from Google Cloud Console → scp to the Mac → with
   `GOG_HOME="$HOME/Library/Application Support/gogcli"`,
   `GOG_KEYRING_BACKEND=file`,
   `GOG_KEYRING_PASSWORD="$(launchctl getenv GOG_KEYRING_PASSWORD)"` (abort
   if empty), run `gog auth credentials <file>` → expect
   `client_secret_in_keyring: true`.
3. **Final OAuth stays in the user's hands**: `bash ~/gog-v3.sh` on the Mac;
   the callback URL is a live credential — never into chat. Any code from an
   earlier attempt is dead; expect a fresh one. If the secret ever transits
   chat (user pasted the file), recommend rotating it later — re-import is
   the same one command.

Completion check: probe returns `invalid_grant` for the dummy code, keyring
import reports `client_secret_in_keyring: true`, and the user's final
`gog auth add` stores a token (`gog auth list --check` clean).

Source: mac-mini gog/Gmail setup lane 2026-10-08 (2026-10-08 skill-mining
pass).
