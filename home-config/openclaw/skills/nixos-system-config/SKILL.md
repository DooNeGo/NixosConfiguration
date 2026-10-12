---
name: "nixos-system-config"
description: "Edit the NixOS system config (system-config/*.nix) — upstream option check, toplevel build verify, user applies via nixos-rebuild switch."
---

# Change the NixOS system configuration

Source of truth: `/home/shared/NixosConfiguration/system-config/*.nix`,
imported by `configuration.nix`. Applying is always the user's step — system
level needs their sudo.

For a setting of the OpenClaw gateway itself, that lives in a separate
home-config flake — see `nix-openclaw-config`.

## Step 1 — audit for an upstream option before writing a custom unit

The pinned nixpkgs often already has a module for what looks like custom work.
Resolve the exact pinned source and search it before hand-rolling anything:

```sh
P=$(nix eval --raw .#nixosConfigurations.nixos.pkgs.path)
ls "$P/nixos/modules/services/networking/" | grep -i <service>
```

Verified example (2026-10-01): a hand-written `systemd.services` oneshot for
`tailscale serve` was replaced by the user with the upstream
`services.tailscale.serve` (`tailscale-serve.nix`), which also generates the
serve config JSON and wires restart triggers. A custom unit duplicates an
option that already exists and drifts from upstream behavior.

Completion check: you can name the module file backing the option you use, or
state why no upstream option exists.

## Layering: system vs home-manager

Before writing config, pick the layer: `environment.systemPackages` and
`systemd.tmpfiles.rules` do NOT exist in home-manager (verified 2026-09-30).
Root-owned state under `/var/lib` is system territory. tmpfiles rules must
create the FULL subdirectory chain — `d /var/lib/whisper-models` does not
create the `ggml/small` link target, and activation fails at build/run
(verified 2026-09-30). Host repos have no git identity for the `openclaw`
user — commit with a one-off `git -c user.name=… -c user.email=…` copied from
recent history; never write `git config` in the repo (verified 2026-10-06).

Layering your own `systemd.services.<x>` on top of an upstream module that
also defines the unit (verified 2026-10-02: `services.sing-box.enable` plus
our custom unit): leave the module's `settings` unset so its `ExecStartPre`
stays out; drop a duplicate `wantedBy` the module already sets; and expect
the module's service user (e.g. `sing-box` instead of root) as a behavioral
change to verify after the switch.

To replace an attribute the module already sets (e.g. `ExecStart`), use the
empty-reset list form — `ExecStart = [ "" "<new command>" ];`. A plain
`lib.mkForce "<command>"` renders a second `ExecStart=` in the drop-in and
systemd refuses the unit (`bad-setting`, "more than one ExecStart"); the
leading empty string is what resets the module's value (verified 2026-10-03
on `sing-box`: bad-setting → active after the fix). Confirm after a switch
with `systemd-analyze verify <unit>.service` and
`systemctl show -p ExecStart <unit>` (exactly one effective argv).

The repo lives at `/home/shared/NixosConfiguration` (owned by mathew,
`drwxrwx---`). Building it as the openclaw user fails at eval with
`error: opening Git repository … is not owned by current user (libgit2 error
code = 7)` — the libgit2 ownership gate, not a real permission problem. Fix
once per user:

```sh
git config --global --add safe.directory /home/shared/NixosConfiguration
```

Write access: the repo dirs are group-writable (`mathew:users`; openclaw
is in `users`), but a file the user's editor re-saved can lose group-write
(`-rw-r--r-- mathew users`) and `edit` then fails EACCES. Do not chase sudo
(password-gated for openclaw — see Step 3 in `assets/systemd-unit-traps.md`) or an ssh route to mathew: a
same-directory replace needs only directory write, which the group grants.
Write the new content to a temp path, `mv` it over the target, `chmod 660`
to restore the group-write the tree normally carries, then `git diff` to
confirm exactly your hunk (verified 2026-10-07 on `system-config/searx.nix`).
In-place writes (shell redirect, python3 `open(..., "w")`, `cp` onto the
target) fail for the same reason the edit tool did; only rename-based swaps
(`mv`, `sed -i`) work.

## Step 2 — verify with a toplevel build and a real exit code

```sh
cd /home/shared/NixosConfiguration
nix build .#nixosConfigurations.nixos.config.system.build.toplevel >/tmp/tb.log 2>&1
echo "exit=$?"
```

Always run eval/build from inside the flake dir (`cd <repo> && nix eval .#…`) —
the former `builtins.getFlake "path:…"` snippet is retired: on the moved repo
it fails with `error: 'shared' is too short to be a valid store path`
(2026-10-06), while the `cd` + `.#` form verified the same day for both a
nested attrset and a list. Canonical for the Nix trio: `nix-openclaw-config`
Step 2 and `nix-dev-env-tooling` Branch 1 cross-reference this flake-eval trap.

Capture the exit status directly; do not infer success from the log tail or a
piped `&& echo OK` — a pipeline reports the pipe's status, not the build's:
`nix build 2>&1 | tail -1 && echo BUILD_OK` prints BUILD_OK even on failure,
and a deprecation warning in the tail reads like success (observed with
`programs.zsh.initExtra`, 2026-10-01). Canonical for the Nix trio:
`nix-openclaw-config` Step 5 cross-references this pipe-status trap. The
toplevel eval also validates the user's uncommitted work in the same tree, so a
passing build is not proof your change is the only one landing.

Never use `nix eval … .config --json` as a validation gate: `--json` serializes
the WHOLE config and forces every lazy assertion `message` attribute, which
trips a nixpkgs bug in `tasks/filesystems.nix` (`error: attribute 'cycle'
missing` in the fileSystems topo-sort assertion message) — on a perfectly
healthy config that builds fine. Verified 2026-10-05: `nix eval
.#…config --json` exited 1 on a committed tree while
`nix eval .#…config.system.build.toplevel` and `nix build` of the same config
succeeded; the false alarm cost a dead-end debugging loop. Gate with plain
`nix eval <attr>` (no `--json`) or a `nix build` instead. If a lazy-attribute
error ever appears, first suspect the serialization path, not your change.

Freeform module settings (searx `settings.yml`, any module-generated
config file) can be verified before any switch: the toplevel build log
names the rendered-file derivation (`…-settings.yml.drv`) — resolve it with
`nix-store -q --outputs /nix/store/…-settings.yml.drv` and grep the returned
path for your keys (verified 2026-10-07: confirmed the searx `outgoing`
proxy block in the generated YAML with one command, before any switch).

A flake only sees git-tracked files: a NEW untracked source file (e.g. a
script referenced by the unit) fails eval with `error: Path
'system-config/<file>' in the repository ... is not tracked by Git` — `git add`
it before evaluating (verified 2026-10-04 on
`system-config/sing-box/fetch-subscription.sh`; the same flake ignores even
`--impure`-read untracked paths). `--dry-run` on the toplevel is a sufficient
eval check when you only need validation, not derivations.

The same eval failure names the path that a relative `./…` reference resolves
to — which is the MODULE's directory, not the repo root. A `file =
./secrets/<name>.age` inside `system-config/sing-box.nix` looked for
`system-config/secrets/…` while the user had created the file in the repo-root
`secrets/`; the fix is `../secrets/<name>.age` (verified 2026-10-04 with
agenix). Read the error's path before assuming the file is missing.

## Step 2b + Step 3 → `assets/systemd-unit-traps.md`

Full text moved to the support file (SKILL.md 10K-char limit): **Step 2b —
NixOS systemd option type coercion** (booleans/attrsets/ints must be strings;
surfaces only at the toplevel build) and **Step 3 — systemd credentials land
under the FULL unit name** (`.service` suffix kept, `CREDENTIALS_DIRECTORY`,
journal-unread triage).

## Step 4 — respect the user's dirty worktree

The user edits these files in their own editor; expect uncommitted hunks, vim
swaps, and staged renames mid-session. Before editing, run `git status
--porcelain` and `git diff` the target file. Never fold the user's in-flight
edits into your commit silently — commit your hunk, or theirs with attribution,
deliberately and separately. `*.swp` is gitignored; a fresh swap file means an
editor session may be live.

## Step 4b → `assets/systemd-unit-traps.md`

Full text moved to the support file: **Step 4b — proxy for the nix daemon**
(nix-daemon environment block, impureEnvVars, 451-vs-proxy asymmetry, manual
drop-in bootstrap before the switch).

## Step 5 — applying is the user's command

System-level changes apply with `sudo nixos-rebuild switch --flake
/home/shared/NixosConfiguration#nixos` from the user's terminal — never run
it yourself. After the user applies, verify the live effect (e.g. `systemctl
status <unit>`, `tailscale serve status`) instead of assuming the switch took.
A `systemd session is degraded` warning in the switch output reports failed
units, not an apply failure — diagnose the units; for ghost home-manager user
units see `nix-openclaw-config` Step 4b.
