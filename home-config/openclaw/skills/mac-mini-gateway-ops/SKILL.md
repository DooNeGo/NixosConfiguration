---
name: "mac-mini-gateway-ops"
description: "Mac-mini gateway start/stop, plugin install, config edit: backed-up, LaunchDaemon-controlled change with a log entry."
---

# Mac-mini gateway operations

Trigger: tasks on the Mac-mini (mac agent config, plugins, lossless, batch
operations). Access: `ssh -o BatchMode=yes worker@100.94.123.27` (Tailscale);
CLI is `/opt/homebrew/bin/openclaw` (not on non-interactive PATH: use `zsh -lc`).

## Rules (order matters)

1. **Backup first**: `cp ~/.openclaw/openclaw.json
   ~/openclaw-backup-<YYYYMMDD>/openclaw.json.pre-<task>-$(date +%H%M)` before any
   change.
2. **Check gateway state**: `lsof -nP -iTCP:18789 -sTCP:LISTEN` (listener =
   running). `openclaw gateway status` does NOT see the daemon: it reports
   "LaunchAgent (not loaded)"; trust its connectivity probe only.
3. **Gateway control**: the gateway is a system LaunchDaemon
   (`/Library/LaunchDaemons/ai.openclaw.gateway.plist`, runs as `worker`,
   starts at boot). The user LaunchAgent is retired: never load it alongside
   the LaunchDaemon.
   Do not use `openclaw gateway start|stop|restart`. Use (NOPASSWD, arguments
   must match the sudoers rule exactly):
   - Start: `~/start_openclaw.sh` = `sudo -n /bin/launchctl bootstrap system /Library/LaunchDaemons/ai.openclaw.gateway.plist`, waits for port 18789.
   - Stop: `~/stop_openclaw.sh` = `sudo -n /bin/launchctl bootout system/ai.openclaw.gateway` (UNVERIFIED).
   - Restart: `sudo -n /bin/launchctl kickstart -k system/ai.openclaw.gateway` (UNVERIFIED).
   - KeepAlive is true: `kill` respawns, only `bootout` stops durably.
4. **Plugin semantics**: `openclaw plugins install` hot-applies only when a
   Gateway is running; with no Gateway it is saved for next start. Therefore
   install the managed plugin FIRST, then remove `load.paths` — the reverse
   order leaves `entries.<plugin>` enabled with no source →
   `configured-unavailable` (docs `tools/plugin.md:331-334`).
5. **Apply config**: if a Gateway IS running, `openclaw plugins reload <plugin>`
   applies edits (restart only if it reports `restartRequired`). Otherwise
   start it with `~/start_openclaw.sh`.
6. **Log incrementally** to `research/mac-batch-c/LOG.md` (never /tmp — it
   gets wiped).

## Inventory / verification

- `openclaw plugins list --enabled --json` after changes
- `openclaw plugins inspect <id>` for a single plugin
- Final check for stopped-gateway changes: no listener on 18789 + config JSON
  valid (`python3 -m json.tool ~/.openclaw/openclaw.json`).

## Completion check

Config change applied, plugins verified via list/inspect, gateway state
matches intent (running/stopped), and log entry written to
`research/mac-batch-c/LOG.md`.
