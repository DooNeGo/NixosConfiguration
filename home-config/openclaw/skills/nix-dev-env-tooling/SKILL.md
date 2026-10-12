---
name: nix-dev-env-tooling
description: android-sdk-license eval error, Gateway misses Nix-installed IDE, NixOS refuses foreign ELF binary (stub-ld) - Nix dev-env tooling fixes.
---

# Nix dev-environment tooling pitfalls

Verified on this host (repo `/home/shared/NixosConfiguration`, flake
`home-config/openclaw`). Three independent branches; each was a multi-step
investigation that these rules collapse to one step.

## Branch 1 — Android SDK license throw at eval

Trigger: `nix eval`/`nix build` fails with "You must accept the following
licenses: - android-sdk-license".

Decision rules (verified against nixpkgs androidenv source):

- The gate is the `licenseAccepted` argument, driven by nixpkgs config
  `android_sdk.accept_license`. **`extraLicenses` in
  `composeAndroidPackages` is a no-op for acceptance** — it only appends
  names to the written license list (proven: identical drvPath with and
  without it). Do not "fix" the error by adding license names there.
- `export NIXPKGS_ACCEPT_ANDROID_SDK_LICENSE=1` does not help with flake
  eval: the variable is read via `builtins.getEnv`, which returns `""` in
  pure evaluation. Only `nix eval --impure` sees it. Do not chase the export.
- Set the config on **every pkgs instance that could instantiate
  androidenv**. This repo's `pkgs-unstable`/`pkgs-stable` imports set only
  `allowUnfree` — an androidenv built from them throws even when the global
  NixOS pkgs accept the license.

Fix shape:

```nix
pkgs = import nixpkgs {
  inherit system;
  config = {
    allowUnfree = true;
    android_sdk.accept_license = true;
  };
};
```

Verify by evaluation, not by reading the diff: eval the composition's
`androidsdk` drvPath (with `--impure`) before and after; the throw must
disappear and the drvPath resolve. Use the `cd <flake-dir> && nix eval .#…`
form — the repo-move flake-eval trap is canonical in `nixos-system-config`
Step 2. Completion check:
the previously-throwing eval succeeds, and the full activation-package
build passes.

## Branch 2 — JetBrains Gateway SSH does not detect the Nix-installed IDE

Trigger: Gateway's "already installed" list on a remote host is empty, or a
symlink like `~/rider` to a valid IDE home is ignored.

Decision rules (verified live on this host):

- Gateway scans exactly two locations on the remote host:
  `~/.cache/JetBrains/RemoteDev/dist` (auto-download target) and
  `~/.cache/JetBrains/RemoteDev/userProvidedDist` (registered IDEs). It
  never scans `~/<name>`, PATH wrappers, or the nix store. The connection
  dialog's "install path" fields set **where to download**, not where an
  existing IDE lives.
- Fix, one command from the IDE home:
  `<ide-home>/bin/<mainProgram>-remote-dev-server registerBackendLocationForGateway`
  — creates the `userProvidedDist/<name>` symlink. No duplicate IDE is
  downloaded. nixpkgs jetbrains packages ship the wrapper (e.g.
  `bin/rider-remote-dev-server`), so the store path works directly.
- A manual `~/.cache` symlink breaks when a rebuild changes the store hash.
  The durable fix is the home-manager module (present in the pinned HM
  source): it removes stale `_nix_store*` registrations and re-runs
  register on every switch.

Durable fix shape:

```nix
programs.jetbrains-remote = {
  enable = true;
  ides = [ pkgs.jetbrains.rider ];
};
```

Verify: run `remote-dev-server.sh remoteDevStatus` — it prints a STATUS
JSON with the current `idePath`; register output must read
"Created the link .../userProvidedDist/<name> pointing to ...". Completion
check: the activation builds, and the registered IDE appears in Gateway's
"already installed" list on next connect (client side — the one step that
must be confirmed by the user).

## Branch 3 — vendor ELF with a foreign interpreter (stub-ld)

Trigger: a vendor single-file native binary (a "generic linux" build that nixpkgs does not package) fails with "Could not start dynamically linked executable… NixOS cannot run dynamically linked executables intended for generic linux environments out of the box".

Decision rules:

- The blocker is the ELF interpreter path (`/lib64/ld-linux-x86-64.so.2`),
  not the shared libs — `ldd` resolves them against the nix glibc fine.
- `patchelf` is not on PATH by default: run it inside
  `nix shell nixpkgs#patchelf -c sh -c '…'`. Calling it bare after the
  `nix shell` command fails with command-not-found (cost a round trip).
- Interpreter: `LDI=$(ls /nix/store/*glibc*/lib/ld-linux-x86-64.so.2 | head -1)`
  then `patchelf --set-interpreter "$LDI" <binary>`. Verify with
  `<binary> --version`; complete when the tool's real command runs.
- Self-updating binaries overwrite themselves on update and revert the patch —
  re-patch or wrap after updates; a store-path glibc interpreter is stable
  across rebuilds while that glibc stays in the closure.
