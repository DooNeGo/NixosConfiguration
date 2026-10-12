---
name: "nix-openclaw-config"
description: "Change a Nix-managed OpenClaw setting (reasoning, models, providers, channels) — edit source, eval, apply with consent; ghost home-manager units."
---

# Change a Nix-managed OpenClaw config

`~/.openclaw/openclaw.json` is a symlink into `/nix/store` and is regenerated on
every build. Editing it directly accomplishes nothing; the source of truth is the
Nix repository.

## Step 1 — find the module and confirm it feeds the gateway

```sh
readlink -f ~/.openclaw/openclaw.json
cd /home/shared/NixosConfiguration && git status --porcelain
grep -rln "openclaw" --include="*.nix" . | head
```

The gateway config is built by a **separate flake**, not the root system flake:

- source module: `home-config/openclaw/openclaw.nix`
- flake that consumes it: `home-config/openclaw/flake.nix`
- output: `homeConfigurations.openclaw` (user `openclaw`)

The root flake's `nixosConfigurations.nixos` builds `home-manager.users.mathew`,
which has **no** `openclaw` attribute. Evaluating `programs.openclaw` under that
path fails with "attribute 'openclaw' missing" — a wrong path, not a broken
config. Use the flake above.

`git status` may show modifications you did not author. Report them separately;
they ship with your apply, so never fold them into your change silently.

CLI config writes are refused. Under `OPENCLAW_NIX_MODE=1` the gateway treats
`openclaw.json` as immutable: `openclaw config set`, `openclaw agents
set-identity`, doctor token generation, and the "Apply recommended config
repairs now?" prompt of `openclaw doctor` all reject with "Config is managed by
Nix". The repo is the only write route. After any interactive doctor run, check
the `openclaw.json` symlink is intact.

When answering a pty prompt via `process send-keys`, know what fires: a mixed
hex call drops invalid entries but still sends the valid ones, and a bare Enter
selects the default "Yes". If `send-keys` reports "cursor key mode is not known
yet", re-check the prompt state after each send instead of assuming keys landed.

Completion check: you can name the exact file and flake output that produce the
live JSON.

## Step 2 — make the edit, then verify by evaluation

Do not judge an edit by reading the diff. Evaluate the module and inspect the
resulting JSON:

```sh
cd /home/shared/NixosConfiguration/home-config/openclaw
nix eval --json .#homeConfigurations.openclaw.config.programs.openclaw.config.<path>
```

Run eval from the flake directory with the `cd` + `.#` form. The repo-move
flake-eval trap and the repo-access rules (group-write loss, tmp+rename swap,
untracked files) are in `nixos-system-config` Steps 1–2; follow them here too.

`apply_patch` is sandboxed to the agent workspace and rejects `/home/shared`
paths, so edit repo files with exec (for example a python3 insertion).

Quote glob patterns in the shell: an unquoted `--include=*.nix` aborts under zsh
with "no matches found".

`nix-instantiate --parse` only checks syntax. Evaluation is what proves your
attribute landed where you intended.

Keep eval path-specific. A whole-config `nix eval --raw
.#homeConfigurations.openclaw.config` dump hangs (over two minutes). When the
config path is deep or unknown, build the activation package and read the JSON
from it:

```sh
nix build .#homeConfigurations.openclaw.activationPackage --no-link --print-out-paths
```

Then read `<gen>/home-files/.openclaw/openclaw.json`, and check it with
`OPENCLAW_CONFIG_PATH=<that json> openclaw config validate --json`. One build can
confirm several edits at once. Do not pick the config with
`ls -t /nix/store/*-openclaw-default.json`: store paths carry mtime 1970-01-01,
so that ordering is arbitrary and can serve a stale file.

Do not substitute `activationPackage.drvPath` equality for that check. On the
wrong flake the drvPath is identical and reads as "no change", and even on the
right flake equality proves nothing about the JSON value. Evaluate the config
path from the Step 2 snippet instead.

Build check exit status: capture it directly (`nix build ... >/tmp/b.log 2>&1;
echo exit=$?`), as `nixos-system-config` Step 2 requires.

## Step 3 — know the resolution order before adding a setting

Resolution-order rules, the gateway auth schema traps, the active-memory plugin
wiring, and schema-lag escape hatches are in
`assets/resolution-and-schema-traps.md`. Read it before adding a
model/provider/channel/tools/skills setting, or when an eval refusal names an
option the docs claim exists.

Per-agent files (a skill or persona for one agent) are in
`assets/per-agent-files.md`. Do not place store-sourced files with `home.file`
for any loader that reads them.

The lossless-claw compaction threshold is in `lossless-compaction-threshold`.

## Step 4b — ghost home-manager units: "I disabled it" but it still runs

A user-manager unit (quadlet, timer, seed service) that still exists although the
config no longer defines it is usually a stale symlink from an old generation,
not live config. Verify, then clean up manually:

1. Confirm the current config is clean:
   `cd /home/shared/NixosConfiguration/home-config/openclaw && nix eval .#homeConfigurations.openclaw.config.<option path>`
   (e.g. `services.podman.enable`, `services.podman.containers`).
2. Confirm the CURRENT generation ships no such unit: resolve
   `readlink ~/.local/state/home-manager/gcroots/current-home`, then list its
   `home-files/.config/systemd/user/`. A live symlink pointing into an old
   `-home-manager-files` store path is the tell.
3. If both are clean, the symlinks under `~/.config/systemd/user/` are orphans.
   home-manager's `cleanOldGen` only deletes entries listed in the OLD
   generation's home-files, so once a unit leaves the config no later switch
   removes its symlinks.
4. Clean up: `systemctl --user disable --now <units>` (some may report "not
   loaded" — fine); locate ALL leftovers with
   `find ~/.config/systemd/user -maxdepth 2 -name '*<name>*'` (stale `.d/` dirs
   and `seeds/` entries too); `rm` only the orphans absent from the current
   generation's files; `systemctl --user daemon-reload`; then
   `systemctl --user --failed` and `reset-failed` for anything left failed.
   Verify with `systemctl --user list-unit-files | grep <name>` (no match) and
   `is-system-running` (running). Generator-owned `linked-runtime` entries
   (e.g. `podman-*`) are normal and stay. Unit removal does not touch container
   data dirs; check them before promising nothing is lost.

A `The user systemd session is degraded` warning during a home-manager switch
reports failed units, not an apply failure. Diagnose the units separately.

## Step 5 — apply only with consent

`home-manager switch` plus a gateway restart is the user's decision. Present the
diff, the eval output, and the unverified parts, then wait. Never apply, and
never commit, on your own initiative.

A generic instruction to execute tasks, even repeated, or approvals given for an
earlier research step, is not config-edit consent. Each config batch needs its
diffs shown and an explicit approval.

On explicit consent ("apply"), run the switch outside the gateway's process tree.
The running gateway keeps the old config in memory until a restart:

```sh
systemd-run --user --scope --unit=openclaw-hm-switch -- home-manager switch --flake /home/shared/NixosConfiguration/home-config/openclaw#openclaw
```

Afterwards verify the LIVE config by loading the resolved `~/.openclaw/openclaw.json`
target with python3; the symlink points at the new generation as soon as the
switch lands. Allowlist and deny changes reach only NEW sessions until the
gateway restarts.

State plainly what you did not run: a full `home-manager build`, or an
end-to-end request proving the value takes effect at runtime, are separate
steps from a clean module evaluation.
