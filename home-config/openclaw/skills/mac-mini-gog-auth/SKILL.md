---
name: mac-mini-gog-auth
description: Mac-mini node — Google account auth (gog) invalid_client recovery; probe client secret in keyring, import fresh secret, final OAuth.
---

# Mac-mini Google account auth (gog) — invalid_client recovery

Trigger: `gog auth add <email>` fails at the code exchange with
`invalid_client` while the browser consent flow itself works. Verified
2026-10-08: the auth URL and consent are fine; the OAuth client secret in the
gog keyring was stale/rejected. gog reads the secret from the KEYRING —
replacing `~/.config/gogcli/client_secret.json` alone changes nothing.

## Step 1 — probe the client creds without exposing the secret

Read the secret into a shell var and length-check it (`echo ${#SEC}`) — never
a placeholder; then `POST https://oauth2.googleapis.com/token` with
client_id, `client_secret=$SEC`, `code=probe-dummy`,
`grant_type=authorization_code`, `redirect_uri=http://localhost`.
`invalid_grant — Malformed auth code` = client ACCEPTED (a code-side
failure; secret is fine). `invalid_client` = secret rejected. Both outputs
verified 2026-10-08.
Pitfall (cost a false "stale secret" diagnosis, withdrawn same day): a
probe curl written with a literal `***` instead of the interpolated
variable tested garbage and "proved" a healthy secret bad. Interpolate and
length-check every time.

## Step 2 — import a fresh secret

User exports `client_secret.json` for the same client_id from Google Cloud
Console → scp to the Mac → with
`GOG_HOME="$HOME/Library/Application Support/gogcli"`,
`GOG_KEYRING_BACKEND=file`,
`GOG_KEYRING_PASSWORD="$(launchctl getenv GOG_KEYRING_PASSWORD)"` (abort
if empty), run `gog auth credentials <file>` → expect
`client_secret_in_keyring: true`.

## Step 3 — final OAuth stays in the user's hands

`bash ~/gog-v3.sh` on the Mac; the callback URL is a live credential — never
into chat. Any code from an earlier attempt is dead; expect a fresh one. If
the secret ever transits chat (user pasted the file), recommend rotating it
later — re-import is the same one command.

## Completion check

Probe returns `invalid_grant` for the dummy code, keyring import reports
`client_secret_in_keyring: true`, and the user's final `gog auth add`
stores a token (`gog auth list --check` clean).