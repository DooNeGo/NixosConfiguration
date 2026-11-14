---
name: rider-bump
description: Bump the pinned Rider and JetBrains Gateway versions in overlays/rider.nix and verify every flake that uses them. Use for "bump Rider", "обнови Rider".
disable-model-invocation: true
argument-hint: "[--rider VERSION] [--gateway VERSION]"
---

# Bump Rider and Gateway

Arguments: $ARGUMENTS

1. Run `scripts/rider-bump.sh $ARGUMENTS`. With no arguments it sets both products to their latest release; `--rider VERSION` or `--gateway VERSION` changes only that product; `--dry-run` shows the diff without writing. It rewrites the version, build number and the hash of every system in `overlays/rider.nix`.
2. Rider is the Remote Development backend for `openclaw-npm` and Gateway the client for `mathew` and `DooNeGo`: both must be on the same release. When the two versions the script printed differ, stop and ask the owner which one to hold back.
3. Verify without touching the locks, in the background: `scripts/flake-update.sh --check nixos DooNeGo mathew openclaw-npm`.
4. A new release can need more than new hashes. When the Linux build fails in `autoPatchelf`, add the missing library to `buildInputs` or, when nixpkgs no longer has it, to `autoPatchelfIgnoreMissingDeps` in the overlay, with a comment saying which Rider component wants it.

The darwin hashes are checked only when the owner builds on the Mac; say so in the report, together with the switch commands for `mathew` and `openclaw-npm`. Commit only when asked.
