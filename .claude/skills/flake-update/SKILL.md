---
name: flake-update
description: Update the lock of every flake in the repo and get all of them building again. Use for "update flakes", "обнови флейки".
disable-model-invocation: true
---

# Update all flakes

Done when `scripts/flake-update.sh` exits 0: every lock went through `nix flake update` and every flake builds (darwin and DooNeGo: evaluates).

1. Run `scripts/flake-update.sh` in the background; the system build can take longer than a foreground command may run. It processes every flake even after a failure, prints the changed inputs and the last 30 log lines of each failure, and ends with one summary line per flake.
2. For each failed flake, read its log (the path is in the summary) and fix the configuration: a renamed or removed option, a dropped package, a changed hash in an overlay. Then rerun only the check: `scripts/flake-update.sh --check <flake>...`.
3. Repeat until `scripts/flake-update.sh --check` passes for all flakes.

Locks change only through `nix flake update`, which the script runs: do not edit a `flake.lock`, and do not restore an old lock to get past a failure. When the breakage is upstream and has no fix in this repo, stop and tell the owner which input and revision broke which flake.

`kokoro` pins nixpkgs by revision in `flake.nix`, so its lock normally stays unchanged; it is still built.

Report: the inputs that changed per flake, each fix made to the configuration and why, and the switch commands for the owner:

```sh
sudo nixos-rebuild switch --flake ./system-config/nixos#nixos
home-manager switch --flake ./home-config/mathew#mathew
home-manager switch --flake ./home-config/openclaw-npm#openclaw-npm
```

The darwin system and `DooNeGo` are switched on the Mac. Commit ("Update flakes") only when asked.
