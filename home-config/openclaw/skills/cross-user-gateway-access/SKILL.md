---
name: cross-user-gateway-access
description: Reach an OpenClaw Gateway from a second OS user — ACP/IDE bridge, token handover, client binary install.
---

# Reach the gateway from a second OS user

Trigger: the Gateway runs as one OS account (e.g. `openclaw`) and someone wants
to drive it from another account on the same machine (e.g. `<user>`) — an ACP
bridge in an IDE, `openclaw acp`, or the Control UI.

Scope note: this is client-side access. No Nix edit is required to make a second
user work; see `nix-openclaw-config` only when the change is a setting in the
module itself.

## Step 1 — the credential is required even on loopback; pick the right kind

A loopback bind still authenticates. Do not assume "same host, so no
credential", and do not let the documentation's loopback/lan auth table imply
it.

Check which credential the gateway accepts BEFORE handing one over — read
`gateway.auth` in the gateway config (via the nix module source). With
`gateway.auth.mode = "trusted-proxy"` and `gateway.auth.token` unset,
`openclaw acp --token-file ~/.secrets/openclaw-gateway-token` fails with
`unauthorized … auth=token … reason=trusted_proxy_missing_header_x-forwarded-for`
in the gateway log. The accepting credential is the password
(`--password-file ~/.secrets/openclaw-gateway-password`). Both files live in
`~/.secrets/` — do not assume the `-token` file is the one a client needs.

For a JetBrains IDE (`~/.jetbrains/acp.json`), use absolute paths (the bridge
user's `~` may differ) and the correct flag:

```json
{"agent_servers": {"OpenClaw": {"command": "/home/openclaw/.nix-profile/bin/openclaw",
  "args": ["acp", "--password-file", "/home/openclaw/.secrets/openclaw-gateway-password",
           "--session", "agent:coordinator:main"]}}}
```

A `--session` key that does not exist is NOT a connection blocker: without
`--require-existing` the bridge creates it lazily on `session/new`; with it,
it fails (`No session found`). Pick an existing key (e.g.
`agent:coordinator:main`) unless a dedicated session is wanted.

Tilde in `--token-file`/`--password-file` args is expanded by the openclaw CLI
itself — do not "fix" it when the bridge user's HOME is right.

Two things look like success and are not:

- an unauthenticated `GET /health` or `GET /status` returns **200** even though
  the WebSocket demands a token — the HTTP surface and the WS auth decision are
  separate;
- piping an `initialize` frame and closing stdin returns **exit 0 with empty
  stdout**, because the bridge dies before the server answers.

Probe it with stdin held open, and read stderr:

```sh
{ printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{}}}'
  sleep 6
} | timeout 20 openclaw acp --url ws://127.0.0.1:18789 2>&1 >/dev/null \
  | grep -i "unauthorized\|token missing"
```

An empty result means the token was accepted. Completion check: the probe either
prints an auth error or does not, and the claim "works without a token" is never
made from a 200 or an exit code.

Where the gateway token lives: nix-openclaw does not put it in
`openclaw.json` — the unit wrapper (`openclaw-export-env.sh`) reads the file
named by `programs.openclaw.environment.OPENCLAW_GATEWAY_TOKEN` at gateway
startup, and interactive shells never receive it. So
`openclaw gateway auth-token --show` fails in a shell by design. Do not attempt
a shell export of the token. When a token value is needed, read
`~/.secrets/openclaw-gateway-token` directly.

## Step 2 — hand over a copy, not a directory grant

The gateway user's home is `0700` and its token file is `0600`, so a second user
cannot even traverse in. Check the path before assuming it is readable:

```sh
namei -l /home/openclaw/.secrets/openclaw-gateway-token
getfacl -p /home/openclaw 2>/dev/null
```

Prefer a one-shot copy the user runs themselves, which leaves the source home
unchanged and is auditable:

```sh
sudo install -Dm600 -o <user> /home/openclaw/.secrets/openclaw-gateway-token \
  /home/<user>/.config/openclaw/gateway.token
```

An ACL on the gateway home (`setfacl -m u:<user>:x`) is a standing grant with no
expiry. Offer it only as the explicit alternative, and get consent before any
permission widening — the token is full gateway authority.

Never print, echo, or paste the token value; confirm with `-l` and perms only.

## Step 3 — the client binary is not on the system PATH

Verify rather than assume a CLI exists for the second user:

```sh
command -v openclaw || echo "absent from PATH"
```

If absent, adding a package to that user's home-manager is the durable fix. Pin
the CLI to the **running gateway's** version, not to whatever the user's flake
resolves: the config schema moves between versions, so a mismatched CLI can
misread config. Verify the resolved version before adding it.

A store path to the gateway's own binary works immediately but breaks on the
next package update — say that, and do not present it as stable.

## Step 4 — connect

```sh
openclaw acp --url ws://127.0.0.1:18789 \
  --password-file ~/.config/openclaw/gateway.password   # or --token-file per Step 1
```

Loopback is shared between users on the host, so a local second user needs no
tunnel. Confirm the listener before promising anything: `ss -ltnp | grep 18789`.

Completion check: the client authenticates, and the user knows which of the
three fixes (token copy, binary, config) was actually required.
