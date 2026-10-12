---
name: "maui-android-build"
description: "Build the MAUI Android app (Wallet.Droid in ~/projects/maui) on NixOS — regenerate tool wrappers, Directory.Build.props build, fix the stale R.java crash."
---

# Build Wallet.Droid (MAUI Android) on NixOS

Trigger: build the Android app in `/home/openclaw/projects/maui`
(`src/Wallet.Droid/Wallet.Droid.csproj`, single target `net10.0-android36.1`).
Three host-specific blockers make a plain `dotnet build` fail; all fixes are
pinned in the repo/`~/.local/share` and only need regeneration, not re-diagnosis.

## Step 1 — wrappers exist and run

NixOS cannot exec the .NET Android pack's generic-Linux ELFs (XA0111), and its
lld rejects argv0 `ld` (XA3007). Wrapped copies live outside /tmp (tmp cleanup
wiped an earlier /tmp tree):

```sh
~/.local/share/maui-build-tools/setup.sh   # idempotent; rebuilds from the newest pack
~/.local/share/maui-build-tools/aapt2wrap/aapt2 version    # must print a version
~/.local/share/maui-build-tools/binutils/bin/ld --version  # must print LLD
```

setup.sh resolves the real glibc loader from `ldd` (`grep -oE
'/nix/store/[^ ]*/ld-linux-x86-64\.so\.2'` — never the unresolved `/lib64/...`
column) and wraps each dynamic ELF. Re-run it after a dotnet workload/pack
upgrade changes the pack version. No Android NDK is present; Debug builds do
not need one.

## Step 2 — build

`/home/openclaw/projects/maui/Directory.Build.props` sets, only when not
already set: `AndroidSdkDirectory=/home/openclaw/.android/sdk` (the SDK is not
auto-detected on this host — XA5300), `Aapt2ToolPath`, and
`AndroidBinUtilsDirectory` to the wrapper tree. Plain build from repo root:

```sh
cd /home/openclaw/projects/maui && dotnet build src/Wallet.Droid/Wallet.Droid.csproj -c Debug
```

Explicit `-p:` overrides still win (props are conditional). Completion check:
exit 0 and a fresh `com.credits.Wallet-Signed.apk` under
`src/Wallet.Droid/bin/Debug/net10.0-android36.1/`. Hundreds of warnings are
normal (NU1608 AndroidX.Tracing.Tracing version constraint, XA4301 duplicate
MLKit `.so`) — only errors block.

Verified 2026-10-06: the props-only end-to-end build is green — plain
`dotnet build src/Wallet.Droid/Wallet.Droid.csproj -c Debug` from repo root,
0 errors, signed APK present; `Directory.Build.props` committed as `1fbbf41`.

## Pitfall — XAJVC7009 zip crash: delete the stale lowercase R stub

`Xamarin.Android.Tasks.ZipArchiveEx` crashes javac output packaging (XAJVC7009)
when a stale generated stub with the OLD lowercase package
`obj/Debug/net10.0-android36.1/android/src/com/credits/wallet/R.java` sits
next to the current `com/credits/Wallet` stubs — the zip container matches
entries case-insensitively. This tree reappeared a day after its first removal
(2026-10-05→10-06), so treat it as recurring:

```sh
rm -rf src/Wallet.Droid/obj/Debug/net10.0-android36.1/android/src/com/credits/wallet
```

then rebuild. On first occurrence this was verified to fix the build and stay
fixed across two rebuilds.

## Pitfall — concurrent builds

Rider (user mathew) may build the same solution concurrently; both write
`obj/` and can race. If intermediates vanish or fail mid-build, re-check state
before blaming the toolchain.

## Pitfall — headless emulator needs ANDROID_HOME and AVD ownership is per-user

Emulator diagnosis only (fix unverified, 2026-10-06): a non-interactive launch
fails with "Cannot find AVD system path. Please define ANDROID_SDK_ROOT" unless
`ANDROID_HOME` is set; AVDs are per-OS-user (`/var/lib/nocow/android-avds/*.avd`
owned by `openclaw`, the human's AVDs by `mathew`) — the other user cannot write
an AVD it does not own.
