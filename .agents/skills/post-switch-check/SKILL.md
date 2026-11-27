---
name: post-switch-check
description: "Check what the owner applied with a switch: the running system, failed units and the journal of changed services. Use for 'я применил конфигурацию, проверяй'."
---

# Check after the owner's switch

Done when the report says whether the running system matches the branch, which units failed or warn, and what only the owner can check.

1. Build the branch toplevel (no output link) and compare it with the running one: `readlink /run/current-system` against `nix build --no-link --print-out-paths ./system-config/nixos#nixosConfigurations.nixos.config.system.build.toplevel`. A difference means the switch was not applied, or was applied from another revision: say so and stop.
2. `systemctl --failed` and `systemctl --user --failed` (for `mathew`: `systemctl --user -M mathew@ --failed`, if it is not permitted say so).
3. For each unit or service the diff touched (`git diff main --stat` on a branch; after a merge `git log --stat --since=<time of the previous system generation>`, see `ls -l --time-style=long-iso /nix/var/nix/profiles/system-*-link`), `journalctl -u <unit> -b -p warning --no-pager | tail -30` (`openclaw-npm` is in `systemd-journal`). A user unit of `mathew` is read with `journalctl _UID=$(id -u mathew) --since <time> --no-pager`; a hung script, with `ps -eo pid,ppid,etimes,args` over its children.
4. Home Manager changes: compare `readlink ~/.local/state/nix/profiles/home-manager` with `home-manager build --no-out-link` of the same flake for the user the agent can read.

If the Codex sandbox blocks a build or a read-only systemd check, retry that command with `sandbox_permissions: require_escalated` through Auto-review. Report access that Linux still denies, such as another user's systemd bus.

Report failures with the log lines. Name what cannot be verified without the owner: a session start, SDDM return, a mount, a reboot.
