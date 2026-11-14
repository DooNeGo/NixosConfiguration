# CLAUDE.md

## Overview

Personal NixOS + Home Manager configuration for the host `nixos` (x86_64-linux, Hyprland desktop, NVIDIA), plus nix-darwin + Home Manager for the owner's `macbook-air-m1` (aarch64-darwin). There is no test suite; verification means evaluating/building the Nix outputs. The darwin outputs cannot be built on this machine: evaluate them here, the owner builds and switches on the Mac. Agents run as `openclaw-npm`, which has no sudo: build and verify, then hand `switch` (`nixos-rebuild`, `home-manager`) and any `chown`/`rm` under `/home` or `/games` to the owner. When a command fails for lack of permission, ask the owner instead of looking for a workaround.

Ignore `openclaw-local/` and other nix-openclaw workspace files (a separate agent), `reports/` and `research_notes/` (untracked research) and `result` in the root.

## Git workflow

Work on a branch, build-verify, and commit only when asked. Merge into `main`, rebase a branch, push and delete a branch only when asked, and rebase only the branch the owner names. The usual sequence is: commit on the branch, then merge, then delete the branch, then rebase the next branch in the queue. `.claude/settings.json` asks before `rebase`, `push`, `branch -D`, `reset --hard`, `clean`, `checkout .` and `restore .`, and denies a force push.

Before a merge into `main` run `/code-review` on the branch and report the findings; merge only on the owner's explicit command ("applied the config" is not one). Squash the branch to its logical commits first (`git rebase -i` does not work here: `git reset --soft $(git merge-base main HEAD)`, then commit again); one concern per commit, documentation as its own commit.

## Where things go

- This file and `.claude/rules/*.md`: instructions for the agent, kept short. A rule with `paths:` loads only with the files it names; put there what matters for a few files, not for every session.
- `docs/<topic>.md`: why a decision was made, measurements, runbooks for the owner (switch, restore, pairing), troubleshooting. Read on demand; a rule or this file points to it with one line and does not repeat it. Add or update the doc in the same branch as the change that makes it true.
- Code comments: only a constraint the code does not show (`.claude/rules/comments.md`); how to run or restore goes to `docs/`.
- Auto-memory: the owner's preferences and decisions that the repo cannot show. Anything the repo already records stays out of it.

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

`lib/pkgs.nix` is a plain function (not a flake) used by the NixOS flake and the home flakes: base nixpkgs `config`, the `pkgs.stable` overlay (`channelsOverlay`), the Rider overlay and `mkPkgs` for Home Manager; each flake passes its own `inputs`, `cudaSupport` stays per host (`extraConfig`). `kokoro/` is standalone and does not use it.

`home-config/shared/*.nix` (git, git-identity, zsh, ssh, rider, dotnet, maui-dev) are plain modules imported by several user configs; one imported by `DooNeGo` must also evaluate on darwin (guard Linux-only parts with `pkgs.stdenv.hostPlatform.isLinux`). `system-config/nixos/configuration.nix` is the import list for system modules. `system-config/shared/` holds system modules meant for both NixOS and nix-darwin: write them only with options both module systems have (`environment.*`, `programs.tmux.extraConfig`), or the darwin host cannot import them.

## Commands (run from repo root)

Flakes only see git-tracked files: a new file needs `git add -N` before any eval/build, otherwise Nix fails with "not tracked by Git" (the `Write` hook in `.claude/settings.json` does it; files made by other means need it by hand). The `Stop` hook runs `scripts/lint.sh` when `.nix`, `.sh` or `.zsh` files changed.

```sh
nix build --no-link ./system-config/nixos#nixosConfigurations.nixos.config.system.build.toplevel   # build the system without applying
nix eval ./system-config/nixos#nixosConfigurations.nixos.config.<opt>    # inspect an option
home-manager build --flake ./home-config/mathew#mathew
home-manager build --flake ./home-config/openclaw-npm#openclaw-npm
nix build ./kokoro#kokoro-ru
nix eval --raw ./system-config/darwin#darwinConfigurations.macbook-air-m1.config.system.build.toplevel.drvPath   # darwin: evaluation only
nix eval --raw ./home-config/DooNeGo#homeConfigurations.DooNeGo.activationPackage.drvPath
scripts/flake-update.sh                               # `nix flake update` for every flake, then build each; --check builds only
scripts/rider-bump.sh                                 # set the Rider/Gateway pin in overlays/rider.nix to the latest release
scripts/lint.sh                                       # deadnix + statix + nixfmt --check over all flakes (config: statix.toml), shellcheck over tracked *.sh, zsh -n over *.zsh
nixfmt <file>.nix                                     # format the files you changed
```

`deadnix --edit` can break flake `outputs`: a closed pattern like `{ self, nixpkgs }:` must keep `...` after `self` is dropped. Rebuild or evaluate every flake after an auto-fix.

`home-config/openclaw-npm/scripts/config-check.sh` validates an OpenClaw config on an isolated temp state dir without touching `~/.openclaw`.

## Users and pins

- Games run under `mathew` (Steam with `PULSE_SINK` set in `steam.nix`); a separate `games` user is out of scope because headless Steam on NVIDIA and per-account Steam login cost more than the isolation is worth. `openclaw-npm` stays a separate non-wheel user for agents and the Rider backend; keep its name, because renaming moves `/home` state (Nix profiles, `~/.openclaw`) for no isolation gain.
- Rider is pinned in one place, `overlays/rider.nix`, used by `mathew` and `DooNeGo` (Remote Development clients) and `openclaw-npm` (backend); versions must match; bump them with `scripts/rider-bump.sh`, which rewrites the hash of every system in that file.

Session start over ssh, Sunshine and Steam Remote Play: `.claude/rules/remote-access.md` (loads with those files); reasons and troubleshooting: `docs/remote-access.md`.

## Verifying a change

| Changed path | Build |
|---|---|
| `system-config/nixos/` | the system `toplevel` |
| `system-config/darwin/` | the darwin `drvPath` eval |
| `system-config/shared/` | the system `toplevel` and the darwin eval |
| `home-config/DooNeGo/` | the `DooNeGo` `drvPath` eval |
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

- Btrfs mounts, backups and settled decisions: `.claude/rules/btrfs.md` (loads with those files); measurements and the runbook: `docs/btrfs.md`.
- Report failures through `system-config/nixos/failure-notify.nix`: add the service to `services.failure-notify.units`, or call `failure-notify report` from a handler. It already delivers to shells and desktop sessions without root touching a session bus, so a unit needs no `OnFailure` or `notify-send` of its own.
- Keep logic out of `.nix` files: a shell script over ~20 lines, or with functions, option parsing, `flock` or `trap`, goes into a `.sh` (zsh: `.zsh`) next to its module, read with `builtins.readFile`; values from Nix reach it through `runtimeEnv`. A short, plain script may stay inline. Writing such a file: `.claude/rules/shell-tools.md`.
- Before hand-writing a systemd unit, check whether the pinned nixpkgs already has an upstream module/option for it.
- Layering: `environment.systemPackages` / `systemd.tmpfiles.rules` are system-level only (not valid in Home Manager). tmpfiles rules must create the full directory chain.
- Secrets use agenix: `secrets.nix` lists recipients (host key only), encrypted files in `secrets/*.age`. Never print or commit plaintext secrets. Create one with `agenix -e secrets/<name>.age` from the repo root after adding it to `secrets.nix`. The murmur password is such a secret (`environmentFile`). The `sing-box` config is generated by `system-config/nixos/sing-box/generate-config.py` from agenix credentials (`resolve-credential.sh`). AmneziaWG under sing-box and the Tailscale exit node: `docs/sing-box-awg.md`.
- `git status` may show lock-file changes you didn't make (e.g. `flake.lock`); report them separately rather than folding them into your change.
- The repo is shared by group `users` (`mathew` and `openclaw-npm`): `.git` must stay group-writable, otherwise commits and branch switches fail with permission errors (fix: `chmod -R g+w .git`). `system-config/nixos/shared-repo-acl.nix` gives the group a recursive default ACL on the repo, so new files stay writable for both users; it takes effect after the owner's `switch`.
