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
which has **no** `openclaw` attribute at all. Evaluating `programs.openclaw`
under that path fails with "attribute 'openclaw' missing" — that is a wrong
path, not a broken config. Do not re-derive the flake layout from scratch.

`git status` may show pre-existing modifications you did not author. Report
them separately; they ship with your apply, so never fold them into your change
silently.

CLI config writes are refused outright: under `OPENCLAW_NIX_MODE=1` the gateway
treats `openclaw.json` as immutable, so `openclaw agents set-identity`,
`openclaw config set`, doctor token generation, and `openclaw doctor`'s
interactive "Apply recommended config repairs now?" all reject with a "Config
is managed by Nix" message — an accidental Yes on that prompt writes nothing
(verified 2026-10-08), but check the openclaw.json symlink is intact after any
interactive doctor run. The repo is the only write route (verified 2026-10-01
with set-identity and token generation — each refusal cost a round trip).
When answering a Yes/No pty prompt via `process send-keys`, know what actually
fires: a mixed hex call drops invalid entries but still sends the valid ones —
the bare Enter that slipped through selected the default "Yes" (2026-10-08,
harmless only because of Nix-mode). If `send-keys` reports "cursor key mode is
not known yet", do not assume keys landed; re-check the prompt state after
each send.

Completion check: you can name the exact file and flake output that produce the
live JSON.

## Step 2 — make the edit, then verify by evaluation

Do not judge an edit by reading the diff. Evaluate the module and inspect the
resulting JSON:

```sh
cd /home/shared/NixosConfiguration/home-config/openclaw
nix eval --json .#homeConfigurations.openclaw.config.programs.openclaw.config.<path>
```

Use the `cd` + `.#` form above — the repo-move flake-eval trap is canonical in
`nixos-system-config` Step 2. Edit repo files
with exec (e.g. a python3 insertion) — `apply_patch` is sandboxed to the agent
workspace and rejects `/home/shared` paths with "Path escapes sandbox root"
(verified 2026-10-06). A repo file that has lost group-write (user's editor
re-save) fails `edit` with plain EACCES — exec-based in-place writes fail the
same way; use the tmp+rename swap from `nixos-system-config`'s repo-access note.

Quote glob patterns in the shell: `--include=*.nix` triggers "no matches found"
in zsh and aborts the command.

`nix-instantiate --parse` only checks syntax. Evaluation is what proves your
attribute landed where you intended.

Verification shortcuts verified 2026-10-06: a **whole-config** `nix eval --raw
.#homeConfigurations.openclaw.config` dump hangs (>2 min, killed) — keep eval
path-specific. When the value's config path is deep or unknown, build instead:
`nix build .#homeConfigurations.openclaw.activationPackage --no-link
--print-out-paths` and read `<gen>/home-files/.openclaw/openclaw.json` (one
build verified five unrelated edits at once, then `OPENCLAW_CONFIG_PATH=<that
json> openclaw config validate --json` → `valid: true`). Do NOT pick the
config with `ls -t /nix/store/*-openclaw-default.json`: every store path has
mtime 1970-01-01, so the ordering is arbitrary and it served a stale file
(threshold 0.3 / summary qwen) that cost several round trips chasing a phantom
mismatch.

Do not substitute `activationPackage.drvPath` equality for that check. On the
wrong flake the drvPath is always identical and reads as "no change" (2026-10-02:
a modelPolicy edit to `home-config/openclaw/openclaw.nix` left the root flake's
mathew activation drvPath untouched — the gateway config lives in the
home-config flake), and even on the right flake equality proves nothing about
the JSON value. Evaluate the config path from Step 2's snippet instead.

## Step 3 + schema/plugin traps → `assets/resolution-and-schema-traps.md`

Also read `assets/per-agent-files.md` for the per-agent workspace-file procedure (hardlink/symlink traps).

Full text moved to the support file (SKILL.md 10K-char limit): **Step 3 — know
the resolution order before adding a default** (thinkingDefault vs
params.thinking, `modelPolicy.allow` keys-as-allowlist, tools allow/deny/
alsoAllow, per-agent skills lists, custom-provider `reasoning` flag + endpoint
probe), **Gateway auth schema traps** (secret-provider naming, trusted-proxy
auth, codeMode `auto`), **active-memory plugin wiring** (manifest keys, exact
agent ids, `lcm_*` tools), and **Step 4 — schema may lag the runtime**
(generated options vs runtime keys, `channels.*` freeformType escape hatch).
Read it before adding a model/provider/channel/tools/skills setting or when an
eval refusal names an option the docs claim exists.

## Step 4b — ghost home-manager units: "I disabled it" but it still runs

A user-manager unit (quadlet, timer, seed service) that exists though the
config no longer defines it is usually stale symlinks from an old generation,
not live config. Verify, then clean up manually:

1. Confirm the current config is clean:
   `cd /home/shared/NixosConfiguration/home-config/openclaw && nix eval .#homeConfigurations.openclaw.config.<option path>`
   (e.g. `services.podman.enable`, `services.podman.containers`).
2. Confirm the CURRENT generation ships no such unit: resolve
   `readlink ~/.local/state/home-manager/gcroots/current-home`, then list its
   `home-files/.config/systemd/user/`. A live symlink dated weeks ago that
   points into an old `-home-manager-files` store path is the tell.
3. If both are clean, the symlinks under `~/.config/systemd/user/` are
   orphans. home-manager's `cleanOldGen` only deletes entries listed in the
   OLD generation's home-files — once a unit leaves the config, no later
   switch ever removes its symlinks (verified 2026-10-06: a podman-openhands
   quadlet enabled by an uncommitted Sep 28 tree kept `enabled` and running
   through every later switch; that dirty-tree store snapshot was since GC'd,
   so the historical definition is unrecoverable).
4. Cleanup (verified 2026-10-06): `systemctl --user disable --now <units>`
   (some may report "not loaded" — fine), locate ALL leftovers with
   `find ~/.config/systemd/user -maxdepth 2 -name '*<name>*'` (stale `.d/`
   dirs and `seeds/` entries too), `rm` the orphan symlinks/units (only
   those absent from the current generation's files),
   `systemctl --user daemon-reload`, then `systemctl --user --failed` and
   `reset-failed` for anything left failed. Verify with
   `systemctl --user list-unit-files | grep <name>` → none and
   `is-system-running` → running; generator-owned `linked-runtime` entries
   (e.g. `podman-*`) are normal and stay. Container data dirs are untouched
   by unit removal — check them before promising nothing is lost.

A `The user systemd session is degraded` warning during a home-manager switch
is a report of failed units in the manager, NOT an apply failure — the config
applied; diagnose the failed units separately.

## Step 5 — apply only with consent

`home-manager switch` plus a gateway restart is a user decision. Present the
diff, the eval output, and the unverified parts, then wait. Never apply, and
never commit, on your own initiative. A generic instruction to execute tasks
("запускай задачи", even repeated, even after research approvals) is NOT
config-edit consent: each config batch still needs its diffs shown and an
explicit approval (verified 2026-10-06: five edits applied after a generic
go-ahead drew "Я не давал команду на выполнение" and a full revert). On
explicit consent ("apply"), run the
switch outside the gateway's process tree — the running gateway keeps the
old config in memory until a restart:

```sh
systemd-run --user --scope --unit=openclaw-hm-switch -- home-manager switch --flake /home/shared/NixosConfiguration/home-config/openclaw#openclaw
```

Verified 2026-10-06 twice (exit=0 each). Afterwards verify the LIVE config by
loading the resolved `~/.openclaw/openclaw.json` target with python3 — the
symlink points at the new generation the moment the switch lands. Allowlist
and deny changes reach only NEW sessions until the gateway restarts.

When you do run a build check, capture its exit status directly
(`nix build ... >/tmp/b.log 2>&1; echo exit=$?`) — the pipe-status trap is
canonical in `nixos-system-config` Step 2.

State plainly what you did not run: a full `home-manager build`, or an
end-to-end request proving the value takes effect at runtime, are separate
steps from a clean module evaluation.
