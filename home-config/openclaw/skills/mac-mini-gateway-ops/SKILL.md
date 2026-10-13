---
name: "mac-mini-gateway-ops"
description: "Mac-mini gateway, ollama, or nix-darwin daemon work: start/stop, plugin and config edits, daemon rebuilds on worker@100.94.123.27."
---

# Mac-mini operations

Trigger: tasks on the Mac mini: gateway start/stop, plugins, config edits,
ollama or sing-box daemons, nix-darwin changes.

## Access and layout

- SSH: `ssh -o BatchMode=yes worker@100.94.123.27` (Tailscale IP). The alias
  `worker` does not resolve from the coordinator; always use the IP.
- CLI: `/opt/homebrew/bin/openclaw` (Homebrew) is not on the non-interactive
  PATH; run it as `zsh -lc '<cmd>'`.
- Config: the live `~/.openclaw/openclaw.json` is not Nix-managed. Edit it with
  `openclaw config set` after a backup (rule 1), then run `openclaw config validate`.
  Memory slot: `memory-lancedb` with ollama embeddings.
- Repo: `/etc/nix-darwin` (system flake `#Mac-mini-Worker`, owned by worker).
  Home Manager was uninstalled from the Mac on 2026-10-13; nothing applies
  `~/configuration/home-config` any more.

## Services

- Gateway `ai.openclaw.gateway`: system LaunchDaemon
  `/Library/LaunchDaemons/ai.openclaw.gateway.plist`, runs as `worker`, listens
  on 18789. Declared in nix-darwin by `/etc/nix-darwin/gateway.nix` (commit
  b8e8963); see "Gateway in nix-darwin".
- Ollama `ollama-worker`: nix-darwin daemon on 127.0.0.1:11434 (see "System
  daemons"). No `org.nix-community.*` Home Manager agent may exist; it would
  hold the same port.
- sing-box `sing-box-worker`: nix-darwin daemon.

## Rules (order matters)

1. **Backup first**: `mkdir -p ~/openclaw-backup-<YYYYMMDD>`, then
   `cp ~/.openclaw/openclaw.json ~/openclaw-backup-<YYYYMMDD>/openclaw.json.pre-<task>-$(date +%H%M)`.
   Done when `cmp` finds the copy identical to the original.
2. **Check gateway state**: `lsof -nP -iTCP:18789 -sTCP:LISTEN` (a listener
   means running). `openclaw gateway status` does NOT see the daemon: its Service
   line is unreliable (it prints "LaunchAgent (not loaded)" or "LaunchAgent
   (unknown)"). Ignore the Service line; trust only the listener and the
   connectivity probe. Done when you know whether a listener PID exists.
3. **Gateway control**: do not use `openclaw gateway start|stop|restart`. Use:
   - Start: `~/start_openclaw.sh`. It runs `sudo -n /bin/launchctl bootstrap system /Library/LaunchDaemons/ai.openclaw.gateway.plist`,
     then waits up to 30 s for port 18789.
   - Stop: `~/stop_openclaw.sh`. It runs `sudo -n /bin/launchctl bootout system/ai.openclaw.gateway`,
     then waits up to 10 s for the port to close.
   - Restart: `sudo -n /bin/launchctl kickstart -k system/ai.openclaw.gateway`.

   All three rely on the NOPASSWD rule in `/etc/sudoers.d/openclaw-gateway`;
   the arguments must match that rule exactly. Stop and restart were not
   re-tested on 2026-10-13.
   `KeepAlive` is true: `kill` respawns the gateway, and only `bootout` stops it
   durably. The user LaunchAgent is retired; never load it alongside the
   LaunchDaemon. Done when rule 2 shows the intended state.
4. **Plugin semantics**: `openclaw plugins install` hot-applies only when a
   Gateway is running; with no Gateway it is saved for next start. Therefore
   install the managed plugin FIRST, then remove `load.paths`. The reverse order
   leaves `entries.<plugin>` enabled with no source, giving
   `configured-unavailable` (docs `tools/plugin.md:331-334`).
5. **Apply config**: if a Gateway IS running, `openclaw plugins reload <plugin>`
   applies edits; restart only if it reports `restartRequired`. Otherwise start
   the gateway with `~/start_openclaw.sh`. Done when `openclaw plugins inspect
   <id>` shows the new state.
6. **Log each change** in the task's `research/<topic>/` file as it happens.
   Never log to `/tmp`; it gets wiped.

## System daemons (nix-darwin)

`/etc/nix-darwin` holds `configuration.nix` (imports), `sing-box.nix`
(`sing-box-worker`), `ollama.nix` (`ollama-worker`), and `gateway.nix`
(`ai.openclaw.gateway`).

Each daemon is declared as `launchd.daemons.<name>` with `serviceConfig`
containing `UserName = "worker"`, `GroupName = "staff"`, `RunAtLoad`,
`KeepAlive`, `ThrottleInterval`, `Umask = 63`, explicit `HOME` and other
environment variables, and log files under `~/Library/Logs/`. Use `.command`
for a program in `/nix/store`; it wraps the program in `/bin/wait4path /nix/store`.
A raw `ProgramArguments` entry pointing at a `/nix/store` path fails at boot
with exit 78. The gateway is the exception (see below).

- Do not set `WorkingDirectory` on a `/nix/store` daemon: its directory may not
  exist at boot. The gateway sets `~/.openclaw`, which always exists.
- Set `HOME` explicitly: ollama keeps its keys and models under `$HOME/.ollama`.
- Run `git add` on every new `.nix` file before building. Flakes ignore
  untracked files, so the build cannot see them.
- Keep secrets out of the repo: `~/.ollama/id_ed25519` stays on the Mac, never
  committed or printed.

## Gateway in nix-darwin

- `gateway.nix` sets `ProgramArguments` directly, not `.command`: node and the
  openclaw CLI come from Homebrew under `/opt/homebrew`, not `/nix/store`, so
  the wait4path wrapper would do nothing.
- The env file `~/.openclaw/service-env/ai.openclaw.gateway.env` is NOT managed
  by nix; `openclaw gateway install` writes it. ProgramArguments only names its
  path. Never read, copy, or print it.
- The plist `Comment` key is not expressible in this nix-darwin revision, so the
  switch drops it. Expected.
- Changing the gateway follows the nix-darwin steps below: edit `gateway.nix`,
  build, compare the plist, get owner approval, then switch.
- A switch that changes the gateway plist unloads and reloads the running
  gateway: a gap of up to ExitTimeOut (20 s) plus startup. Tell the owner before
  switching.
- Run that switch from a plain ssh session (tmux or nohup keeps it alive if ssh
  drops), not from a process that descends from the gateway, such as an agent
  exec tool or a Telegram-driven session. The unload kills that parent and can
  leave the plist half-copied or deleted.
- Dropping the `gateway.nix` import and switching later deletes the plist and
  stops the gateway (the stale-removal loop). Do this only in an owner-approved
  window.
- Rollback, either: (a) `git revert` the gateway commit and switch in a window.
  This removes the plist and stops the gateway, so follow with (b). Or (b)
  restore `~/backups/ai.openclaw.gateway.plist.handwritten.2026-10-13` over
  `/Library/LaunchDaemons/ai.openclaw.gateway.plist` (root-owned; the worker's
  sudo rights for that copy are unverified), then run `~/start_openclaw.sh`.
  Restoring the file while the import is still present is overwritten by the
  next switch.

## Changing a nix-darwin daemon

1. **Baseline (read-only)**: `lsof -nP -iTCP:<port> -sTCP:LISTEN` and
   `git -C /etc/nix-darwin status --short`. Done when you have recorded the
   current listener (or none) and any uncommitted files.
2. **Edit and stage**: edit the `.nix` file and `git add` new files. Done when
   `git status --short` shows the new file as `A`.
3. **Build (no sudo)**: in a scratch directory outside the repo, run
   `darwin-rebuild build --flake /etc/nix-darwin#Mac-mini-Worker`. Done when the
   exit code is 0.
4. **Compare the plist**: `nix-store -qR "$(readlink result)" | grep '<label>.plist$'`
   finds the built plist. Run `plutil -p` on it and on
   `/Library/LaunchDaemons/<label>.plist`, then `diff` the two outputs. Done
   when the diff shows only the intended keys (for the gateway, also the
   expected `Comment` line).
5. **Owner approval gate**: report the diff and stop. Do not switch without the
   owner's explicit approval. For the gateway, say the gateway will restart.
6. **Switch (after approval only)**: `sudo darwin-rebuild switch --flake /etc/nix-darwin#Mac-mini-Worker`.
   If the sudo password comes from a file, pipe it to `sudo -S` on stdin; never
   print it or write it to a log. For the gateway, run it per "Gateway in
   nix-darwin". Done when the switch exits 0. (The `--flake` form on switch is
   unverified; the build form was verified 2026-10-13.)
7. **Checks**: `lsof` on the port shows the daemon's process; `ps -axo user,pid,command`
   shows user `worker` for it; the daemon log (for ollama,
   `~/Library/Logs/ollama-worker.log`) shows no crash loop. Done when all three
   match the intent.
8. **Commit (owner approval required)**: the step-5 approval covers the switch
   only. After step 7 passes, ask the owner before running `git commit` in
   `/etc/nix-darwin`; commit only on an explicit yes, with a message that names
   the daemon. Done when the owner has approved and the commit exists and
   `git status` shows no leftover change for it, or the owner declined and the
   change is reported as uncommitted.

## Moving a service between managers

Moving a service from Home Manager or a user LaunchAgent into a nix-darwin
daemon: remove the old agent first, confirm it is gone, then switch. Two
managers on one port leave the second unable to bind, and KeepAlive restarts it
in a loop.

## Inventory / verification

- `openclaw plugins list --enabled --json` after changes
- `openclaw plugins inspect <id>` for a single plugin
- Stopped-gateway changes: no listener on 18789, and `openclaw config validate`
  passes.

## Completion check

Config change applied, plugins verified via list/inspect, gateway state matches
intent (running or stopped), and each change logged in the task's
`research/<topic>/` file. Daemon changes also pass the nix-darwin steps in
order: build, plist diff, owner approval, switch, checks, then a commit only
after separate owner approval.
