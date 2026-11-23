# AGENTS.md

## Overview

Personal NixOS + Home Manager configuration for the host `nixos` (x86_64-linux, Hyprland desktop, NVIDIA), plus nix-darwin + Home Manager for the owner's `macbook-air-m1` (aarch64-darwin). Verification means evaluating or building the changed Nix outputs and running the component tests listed below. The darwin outputs cannot be built on this machine: evaluate them here, the owner builds and switches on the Mac. Build and verify, then hand `switch` (`nixos-rebuild`, `home-manager`) and any `chown`/`rm` under `/home` or `/games` to the owner, except a named path of the agent user `openclaw-npm` that the owner explicitly asks to delete.

Ignore `openclaw-local/` and other nix-openclaw workspace files (a separate agent), `reports/` and `research_notes/` (untracked research) and `result` in the root.

## Git workflow

Work on a branch, except for a simple, quick change (adding a package, changing one setting), which goes straight to `main`. On a branch, commit a finished group without asking; on `main`, only when asked. Change `main` (merge into it, rebase or reset it, `branch -f`), push and delete an unmerged branch only on the owner's explicit command ("applied the config" is not one), and rebase only the branch the owner names. To look at an older commit use `git switch --detach <hash>`; to compare with a clean tree use `git worktree add --detach <dir> HEAD`, not `git stash` (it fails on `git add -N` entries and hides your work). The Codex Git hook blocks protected operations, including push, updates to `main`, and commands that discard work (`reset --hard`, `clean`, `checkout .`, `restore .`). After reviewing and authorizing a protected operation, the owner runs it from their terminal. Force pushes are prohibited. See `docs/codex-harness.md`.

## Where things go

`docs/<topic>.md` is reference documentation, written as for another developer: how a part works, why it is built that way, the measurements behind the current settings, runbooks for the owner (switch, restore, pairing) and troubleshooting. It describes the current state; what was tried and dropped goes to auto-memory. Use the topic pointers below to find the relevant instructions and docs. Add or update the doc in the same branch as the change that makes it true.

## Multiple independent flakes

This repo is **not** one flake. Each flake has its own `flake.lock`, no flake pulls in another, and the repo root has no flake:

| Flake | Output | Applies to |
|---|---|---|
| `system-config/nixos/` | `nixosConfigurations.nixos` | the whole system |
| `tools/box/` | `packages.<system>.podman`, `lib` | not a configuration: the test box (`tools/box/box`, container or VM) that applies layers to the flakes above |
| `system-config/darwin/` | `darwinConfigurations.macbook-air-m1` (nix-darwin, nix-homebrew) | the MacBook system |
| `home-config/DooNeGo/` | `homeConfigurations.DooNeGo` | the MacBook user (standalone Home Manager, like the Linux users) |
| `home-config/mathew/` | `homeConfigurations.mathew` | desktop user `mathew` (Hyprland, waybar, kitty…) |
| `home-config/openclaw-npm/` | `homeConfigurations.openclaw-npm` | agent/dev user (MAUI/Android SDK, Rider, nix-ld) |

`lib/pkgs.nix` is a plain function, not a flake: the NixOS flake and the home flakes call it with their own `inputs`.

## Commands (run from repo root)

Flakes see Git-tracked files. Use `git add -N` for new inputs before evaluating or building. The Codex patch hook registers added files and formats changed Nix files. For shell-generated changes and sessions without trusted hooks, run those steps explicitly. The `Stop` hook runs `scripts/lint.sh` when `.nix`, `.sh`, `.zsh` or `tools/box` files changed.

```sh
nix build --no-link ./system-config/nixos#nixosConfigurations.nixos.config.system.build.toplevel   # build the system without applying
nix eval ./system-config/nixos#nixosConfigurations.nixos.config.<opt>    # inspect an option
scripts/lint.sh                                       # deadnix + statix + nixfmt --check over all flakes (config: statix.toml), shellcheck over tracked *.sh and the `tools/box` fixtures, zsh -n over *.zsh, ruff over `tools/box`; run it without a pipe, `| tail` hides the exit status
```

`home-config/openclaw-npm/scripts/config-check.sh` validates an OpenClaw config on an isolated temp state dir without touching `~/.openclaw`.

## Users and pins

- Games run under `mathew` (Steam with `PULSE_SINK` set in `steam.nix`); a separate `games` user is out of scope because headless Steam on NVIDIA and per-account Steam login cost more than the isolation is worth. `openclaw-npm` stays a separate non-wheel user for agents and the Rider backend; keep its name, because renaming moves `/home` state (Nix profiles, `~/.openclaw`) for no isolation gain.
- Rider is pinned in one place, `overlays/rider.nix`, used by `mathew` and `DooNeGo` (Remote Development clients) and `openclaw-npm` (backend); versions must match; bump them with the `rider-bump` skill.
  Gateway cannot connect or shows "error in the connection provider": `docs/rider-remote.md`.

Session start over ssh, Sunshine and Steam Remote Play: `.codex/instructions/remote-access.md`; reasons and troubleshooting: `docs/remote-access.md`.

To test what the owner's `switch` cannot check safely (session order, hyprlock, a user unit of any Home Manager user), run it in the box: a rootless-podman container or a QEMU VM (skill `box-test`; how it works: `docs/box.md`).

## Verifying a change

| Changed path | Build |
|---|---|
| `system-config/nixos/` | the system `toplevel` (first command above); for `sing-box/` also `python3 -B -m unittest discover -s system-config/nixos/sing-box -p 'test_*.py'` |
| `tools/box/` | `tools/box/box build --system nixos --home mathew` (and `--backend vm`), `python3 -m unittest discover -s tools/box/tests -t tools/box` and `scripts/lint.sh` (ruff) |
| `system-config/darwin/` | the darwin eval: `nix eval --raw ./system-config/darwin#darwinConfigurations.macbook-air-m1.config.system.build.toplevel.drvPath` (evaluation only) |
| `system-config/shared/` | the system `toplevel` and the darwin eval |
| `home-config/DooNeGo/` | the `DooNeGo` eval: `nix eval --raw ./home-config/DooNeGo#homeConfigurations.DooNeGo.activationPackage.drvPath` |
| `home-config/mathew/` | `home-manager build --no-out-link --flake ./home-config/mathew#mathew` |
| `home-config/openclaw-npm/` | `home-manager build --no-out-link --flake ./home-config/openclaw-npm#openclaw-npm` |
| `home-config/shared/` | both home builds and the `DooNeGo` eval |
| `lib/`, `overlays/` | both home builds, the system build and the `DooNeGo` eval |
| `assets/sofa/` | the system `toplevel` |
| `assets/wallpapers/` | the `mathew` home build |

When a build fails, rerun it without output redirection and read `2>&1 | tail -30`. Report to the owner the exact `switch` commands and what could not be verified without running (a service start, a session, a mount).

In a review (code-review skill), leave out pure style and naming.

## Conventions and gotchas

- Garbage collection (`nh`), generation count, journal limits, nix-daemon `TMPDIR`: `docs/nix-maintenance.md`.
- Btrfs mounts, backups and settled decisions: `.codex/instructions/btrfs.md`; measurements and the runbook: `docs/btrfs.md`.
- Before hand-writing a systemd unit, check whether the pinned nixpkgs already has an upstream module/option for it. Other conventions for `.nix` files (failure reporting, logic in `.sh`, layering, shared modules): `.codex/instructions/nix.md`.
- Secrets use agenix (`secrets.nix` lists recipients, encrypted files are `secrets/*.age`): never print or commit plaintext secrets. Creating one and the generated `sing-box` config: `.codex/instructions/secrets.md`; AmneziaWG under sing-box and the Tailscale exit node: `docs/sing-box-tunnels.md`.
- `git status` may show lock-file changes you didn't make (e.g. `flake.lock`); report them separately rather than folding them into your change.
- The repo is shared by group `users` (`mathew` and `openclaw-npm`). If commits or branch switches fail with a permission error, `.git` has lost group write: `chmod -R g+w .git`. `system-config/nixos/shared-repo-acl.nix` gives the group a recursive default ACL on the repo, so new files stay writable for both users.

## Topic instructions

Read the matching files before editing. Paths are relative to the repository root.

| Scope | Instructions |
|---|---|
| `*.nix` | `.codex/instructions/nix.md` and `.codex/instructions/comments.md` |
| `*.sh`, `*.zsh` | `.codex/instructions/shell-tools.md` and `.codex/instructions/comments.md` |
| `tools/box/**` | `.codex/instructions/box.md` |
| `system-config/nixos/{file-systems,backup,hardware-configuration}.nix`, `docs/btrfs.md`, `scripts/btrfs-*.sh` | `.codex/instructions/btrfs.md` |
| `system-config/nixos/{hyprland-session,steam-bigpicture-session,remote-access,sddm,audio}.nix`, `home-config/mathew/hyprland/{session,monitors}.lua`, `home-config/mathew/hyprlock-initial.nix`, `docs/remote-access.md` | `.codex/instructions/remote-access.md` |
| `secrets.nix`, `secrets/**`, `system-config/nixos/sing-box{.nix,/**}` | `.codex/instructions/secrets.md` |
| `.codex/config.toml`, `.codex/hooks.json`, `.codex/hooks/**` | `.codex/instructions/settings-json.md` |

Project skills live in `.agents/skills/`. The workspace NixOS MCP server, hook trust and verification are documented in `docs/codex-harness.md`.
