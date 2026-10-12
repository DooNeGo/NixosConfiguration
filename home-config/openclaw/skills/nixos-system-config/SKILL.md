---
name: "nixos-system-config"
description: "Edit the NixOS system config (system-config/*.nix) — upstream option check, toplevel build verify, user applies via nixos-rebuild switch."
---

# Change the NixOS system configuration

Source of truth: `/home/shared/NixosConfiguration/system-config/*.nix`,
imported by `configuration.nix`. Applying is always the owner's step — system
level needs their sudo.

For a setting of the OpenClaw gateway itself, see `nix-openclaw-config`: that
lives in a separate home-config flake.

## Step 1 — audit for an upstream option before writing a custom unit

The pinned nixpkgs often already has a module for what looks like custom work.
Resolve the exact pinned source and search it before hand-rolling anything:

```sh
P=$(nix eval --raw .#nixosConfigurations.nixos.pkgs.path)
ls "$P/nixos/modules/services/networking/" | grep -i <service>
```

Example: a hand-written `systemd.services` oneshot for `tailscale serve` duplicated
the upstream `services.tailscale.serve` option (`tailscale-serve.nix`), which
also generates the serve config JSON and wires restart triggers. A custom unit
duplicates an option that already exists and drifts from upstream behavior.

Completion check: you can name the module file backing the option you use, or
state why no upstream option exists.

## Layering: system vs home-manager

Before writing config, pick the layer: `environment.systemPackages` and
`systemd.tmpfiles.rules` do NOT exist in home-manager. Root-owned state under
`/var/lib` is system territory.

tmpfiles rules must create the FULL subdirectory chain: `d /var/lib/whisper-models`
does not create the `ggml/small` link target, and activation fails at build or run.

The host repos have no git identity for the `openclaw` user. Commit with a
one-off `git -c user.name=… -c user.email=…` copied from recent history; never
write `git config` in the repo.

Layering your own `systemd.services.<x>` on top of an upstream module that also
defines the unit (e.g. `services.sing-box.enable` plus a custom unit): leave the
module's `settings` unset so its `ExecStartPre` stays out, drop any duplicate
`wantedBy` the module already sets, and verify the module's service user (e.g.
`sing-box` instead of root) as a behavioral change after the switch.

To replace an attribute the module already sets (e.g. `ExecStart`), use the
empty-reset list form: `ExecStart = [ "" "<new command>" ];`. A plain
`lib.mkForce "<command>"` renders a second `ExecStart=` and systemd refuses the
unit (`bad-setting`, "more than one ExecStart"); the leading empty string resets
the module's value. Confirm after a switch with `systemd-analyze verify <unit>.service`
and `systemctl show -p ExecStart <unit>` (exactly one effective argv).

## Repo access: the libgit2 ownership gate and group-write

The repo lives at `/home/shared/NixosConfiguration`, owned by the owner account
(`drwxrwx---`). Building it as the `openclaw` user fails at eval with
`error: opening Git repository … is not owned by current user (libgit2 error
code = 7)`. That is the ownership gate, not a permission problem. Fix it once per
user:

```sh
git config --global --add safe.directory /home/shared/NixosConfiguration
```

The repo directories are group-writable (`<owner>:users`; openclaw is in `users`),
but a file the owner's editor re-saved can lose group-write (`-rw-r--r--`) and
`edit` then fails with EACCES. Do not chase sudo (password-gated for openclaw; see
`assets/systemd-unit-traps.md`) or an ssh route to the owner account. A
same-directory replace needs only directory write, which the group grants:
write the new content to a temp path, `mv` it over the target, `chmod 660` to
restore the group-write the tree carries, then `git diff` to confirm exactly your
hunk. In-place writes (shell redirect, python3 `open(..., "w")`, `cp` onto the
target) fail the same way the edit tool did; only rename-based swaps (`mv`,
`sed -i`) work.

## Step 2 — verify with a toplevel build and a real exit code

```sh
cd /home/shared/NixosConfiguration
nix build .#nixosConfigurations.nixos.config.system.build.toplevel >/tmp/tb.log 2>&1
echo "exit=$?"
```

Always run eval and build from inside the flake directory (`cd <repo> && nix eval .#…`).
The older `builtins.getFlake "path:…"` form is retired: on the moved repo it fails
with `error: 'shared' is too short to be a valid store path`.

Capture the exit status directly. Do not infer success from a piped log tail:
`nix build 2>&1 | tail -1 && echo BUILD_OK` prints BUILD_OK even on failure, and a
deprecation warning in the tail reads like success. The toplevel eval also
validates the owner's uncommitted work in the same tree, so a passing build does
not prove your change is the only one landing.

Never use `nix eval … .config --json` as a validation gate. `--json` serializes
the WHOLE config and forces every lazy assertion `message`, which trips a nixpkgs
bug in `tasks/filesystems.nix` (`error: attribute 'cycle' missing` in the
fileSystems topo-sort message) on a config that builds fine. Gate with plain
`nix eval <attr>` (no `--json`) or `nix build`. If a lazy-attribute error appears,
suspect the serialization path first, not your change.

Freeform module settings (searx `settings.yml`, any module-generated file) can be
checked before any switch: the toplevel build log names the rendered-file
derivation (`…-settings.yml.drv`). Resolve it with
`nix-store -q --outputs /nix/store/…-settings.yml.drv` and grep the output for your keys.

A flake sees only git-tracked files. A NEW untracked source file (e.g. a script the
unit references) fails eval with `Path 'system-config/<file>' in the repository ...
is not tracked by Git`: `git add` it before evaluating. `--dry-run` on the toplevel
is a sufficient eval check when you need validation, not derivations.

A relative `./…` reference resolves against the MODULE's directory, not the repo
root. `file = ./secrets/<name>.age` inside `system-config/sing-box.nix` looks for
`system-config/secrets/…`; if the file is in the repo-root `secrets/`, use
`../secrets/<name>.age`. Read the error's path before assuming the file is missing.

## Step 2b + Step 3 → `assets/systemd-unit-traps.md`

Full text is in the support file: **Step 2b — NixOS systemd option type coercion**
(booleans, attrsets and ints must be strings; surfaces only at the toplevel build)
and **Step 3 — systemd credentials land under the FULL unit name** (`.service`
suffix kept, `CREDENTIALS_DIRECTORY`, journal-unread triage).

## Step 4 — respect the owner's dirty worktree

The owner edits these files in their own editor; expect uncommitted hunks, vim
swaps, and staged renames mid-session. Before editing, run `git status --porcelain`
and `git diff` the target file. Never fold the owner's in-flight edits into your
commit silently: commit your hunk, or theirs with attribution, deliberately and
separately. `*.swp` is gitignored; a fresh swap file means an editor session may be live.

## Step 4b → `assets/systemd-unit-traps.md`

Full text is in the support file: **Step 4b — proxy for the nix daemon** (daemon
environment block, impureEnvVars, the 451-versus-proxy asymmetry, and the manual
drop-in bootstrap before the switch).

## Step 5 — applying is the owner's command

System-level changes apply with `sudo nixos-rebuild switch --flake
/home/shared/NixosConfiguration#nixos` from the owner's terminal. Never run it
yourself. After the owner applies, verify the live effect (e.g. `systemctl status
<unit>`, `tailscale serve status`) instead of assuming the switch took. A
`systemd session is degraded` warning in the switch output reports failed units,
not an apply failure: diagnose the units. For ghost home-manager user units see
`nix-openclaw-config` Step 4b.
