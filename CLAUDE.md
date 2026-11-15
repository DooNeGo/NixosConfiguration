# CLAUDE.md

## Overview

Personal NixOS + Home Manager configuration for the host `nixos` (x86_64-linux, Hyprland desktop, NVIDIA), plus nix-darwin + Home Manager for the owner's `macbook-air-m1` (aarch64-darwin). There is no test suite; verification means evaluating/building the Nix outputs. The darwin outputs cannot be built on this machine: evaluate them here, the owner builds and switches on the Mac. Build and verify, then hand `switch` (`nixos-rebuild`, `home-manager`) and any `chown`/`rm` under `/home` or `/games` to the owner.

Ignore `openclaw-local/` and other nix-openclaw workspace files (a separate agent), `reports/` and `research_notes/` (untracked research) and `result` in the root.

## Git workflow

Work on a branch, build-verify, and commit only when asked: one concern per commit, documentation as its own commit. Merge into `main`, rebase, push and delete an unmerged branch only on the owner's explicit command ("applied the config" is not one), and rebase only the branch the owner names. `.claude/hooks/guard-git.sh` asks, in any spelling, before those commands and before commands that discard work (`reset --hard`, `clean`, `checkout .`, `restore .`); `.claude/settings.json` keeps prefix rules for them as a fallback and denies a force push.

## Where things go

`docs/<topic>.md` is reference documentation, written as for another developer: how a part works, why it is built that way, the measurements behind the current settings, runbooks for the owner (switch, restore, pairing) and troubleshooting. It describes the current state; what was tried and dropped goes to auto-memory. A rule or this file points to a doc with one line that names the symptom and does not repeat the doc. Add or update the doc in the same branch as the change that makes it true.

## Multiple independent flakes

This repo is **not** one flake. Each flake has its own `flake.lock`, no flake pulls in another, and the repo root has no flake:

| Flake | Output | Applies to |
|---|---|---|
| `system-config/nixos/` | `nixosConfigurations.nixos` | the whole system |
| `system-config/darwin/` | `darwinConfigurations.macbook-air-m1` (nix-darwin, nix-homebrew) | the MacBook system |
| `home-config/DooNeGo/` | `homeConfigurations.DooNeGo` | the MacBook user (standalone Home Manager, like the Linux users) |
| `home-config/mathew/` | `homeConfigurations.mathew` | desktop user `mathew` (Hyprland, waybar, kitty…) |
| `home-config/openclaw-npm/` | `homeConfigurations.openclaw-npm` | agent/dev user (MAUI/Android SDK, Rider, nix-ld) |
| `kokoro/` | Russian TTS packages (`kokoro-ru`, `ruaccent`, `pycrfsuite`, pinned data trees) + `cli/kokoro_cli.py` | standalone; pinned to its own nixpkgs rev |

`lib/pkgs.nix` is a plain function, not a flake: the NixOS flake and the home flakes call it with their own `inputs`; `kokoro/` does not use it.

## Commands (run from repo root)

Flakes only see git-tracked files: a new file needs `git add -N` before any eval/build, otherwise Nix fails with "not tracked by Git" (the `Write` hook in `.claude/settings.json` does it; files made by other means need it by hand). The `Stop` hook runs `scripts/lint.sh` when `.nix`, `.sh` or `.zsh` files changed.

```sh
nix build --no-link ./system-config/nixos#nixosConfigurations.nixos.config.system.build.toplevel   # build the system without applying
nix eval ./system-config/nixos#nixosConfigurations.nixos.config.<opt>    # inspect an option
scripts/lint.sh                                       # deadnix + statix + nixfmt --check over all flakes (config: statix.toml), shellcheck over tracked *.sh, zsh -n over *.zsh
```

`home-config/openclaw-npm/scripts/config-check.sh` validates an OpenClaw config on an isolated temp state dir without touching `~/.openclaw`.

## Users and pins

- Games run under `mathew` (Steam with `PULSE_SINK` set in `steam.nix`); a separate `games` user is out of scope because headless Steam on NVIDIA and per-account Steam login cost more than the isolation is worth. `openclaw-npm` stays a separate non-wheel user for agents and the Rider backend; keep its name, because renaming moves `/home` state (Nix profiles, `~/.openclaw`) for no isolation gain.
- Rider is pinned in one place, `overlays/rider.nix`, used by `mathew` and `DooNeGo` (Remote Development clients) and `openclaw-npm` (backend); versions must match; bump them with the `rider-bump` skill.

Session start over ssh, Sunshine and Steam Remote Play: `.claude/rules/remote-access.md` (loads with those files); reasons and troubleshooting: `docs/remote-access.md`.

## Verifying a change

| Changed path | Build |
|---|---|
| `system-config/nixos/` | the system `toplevel` (first command above) |
| `system-config/darwin/` | the darwin eval: `nix eval --raw ./system-config/darwin#darwinConfigurations.macbook-air-m1.config.system.build.toplevel.drvPath` (evaluation only) |
| `system-config/shared/` | the system `toplevel` and the darwin eval |
| `home-config/DooNeGo/` | the `DooNeGo` eval: `nix eval --raw ./home-config/DooNeGo#homeConfigurations.DooNeGo.activationPackage.drvPath` |
| `home-config/mathew/` | `home-manager build --flake ./home-config/mathew#mathew` |
| `home-config/openclaw-npm/` | `home-manager build --flake ./home-config/openclaw-npm#openclaw-npm` |
| `home-config/shared/` | both home builds and the `DooNeGo` eval |
| `lib/`, `overlays/` | both home builds, the system build and the `DooNeGo` eval |
| `assets/sofa/` | the system `toplevel` |
| `assets/wallpapers/` | the `mathew` home build |
| `kokoro/` | `nix build ./kokoro#kokoro-ru` |

When a build fails, rerun it without output redirection and read `2>&1 | tail -30`. Report to the owner the exact `switch` commands and what could not be verified without running (a service start, a session, a mount).

In a review (`/code-review`), report what causes wrong behaviour, a failing check or a misleading result; leave out pure style and naming.

## Conventions and gotchas

- Garbage collection (`nh`), generation count, journal limits, nix-daemon `TMPDIR`: `docs/nix-maintenance.md`.
- Btrfs mounts, backups and settled decisions: `.claude/rules/btrfs.md` (loads with those files); measurements and the runbook: `docs/btrfs.md`.
- Before hand-writing a systemd unit, check whether the pinned nixpkgs already has an upstream module/option for it. Other conventions for `.nix` files (failure reporting, logic in `.sh`, layering, shared modules): `.claude/rules/nix.md`.
- Secrets use agenix (`secrets.nix` lists recipients, encrypted files are `secrets/*.age`): never print or commit plaintext secrets. Creating one and the generated `sing-box` config: `.claude/rules/secrets.md`; AmneziaWG under sing-box and the Tailscale exit node: `docs/sing-box-awg.md`.
- `git status` may show lock-file changes you didn't make (e.g. `flake.lock`); report them separately rather than folding them into your change.
- The repo is shared by group `users` (`mathew` and `openclaw-npm`). If commits or branch switches fail with a permission error, `.git` has lost group write: `chmod -R g+w .git`. `system-config/nixos/shared-repo-acl.nix` gives the group a recursive default ACL on the repo, so new files stay writable for both users.
