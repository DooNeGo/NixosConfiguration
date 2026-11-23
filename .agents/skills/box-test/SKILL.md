---
name: box-test
description: "Test a change in the box (NixOS container or VM) when a build is not enough: sessions, hyprlock, user units. For 'проверь в box', 'запусти box test'. After a switch: post-switch-check."
---

# Test a change in the box

Done when the report shows the `box test` output for the combination the change touches, says which failures are regressions and which are a missing environment, and names what only the owner's stream can check.

1. Build first (`home-manager build`, `nixos-rebuild build`; the table in `AGENTS.md`): the box is for what a build cannot show.
2. Pick the combination from the changed paths: `system-config/nixos` is `--system nixos`; `home-config/<user>` is `--home <user>` together with `--system nixos` (the session of a home needs the system). A new file needs `git add -N`.
3. Run `tools/box/box test --system nixos --home <user>` (about 40 s). The container is the default; add `--backend vm` (also about 1 minute) when the change depends on a whole boot, the real SDDM, udev, sysfs or mounts (`docs/box.md`, Container or VM), and run both when unsure. `--tests NAME...` (names or shell patterns) runs selected checks; `--keep` leaves the instance for `box exec` and `box fixture` while you look.
4. For each FAIL read its output, then decide:
   - the change broke it (a unit, an order or a file the change touches): fix the change and rerun;
   - an unrelated unit fails because the container lacks something: apply the rule of the Layers section of `docs/box.md` to that unit only. Never silence a unit the change touches; a fix that needs more container privileges goes to the owner.
5. A change that adds behaviour no check sees gets a check (and a fixture when it needs a state): `docs/box.md`, Fixtures and checks. Run it and show the output.
6. Report the output, the layer changes and why, and what the box does not test (`docs/box.md`, Session user in the container and Limits). The owner's stream is the last check.

`box` says when the user manager lacks the group `video`; the owner restarts it. A permission error is a question to the owner.
