# Test user

`testuser` is a permanent playground for the agent: a separate account with its own headless Hyprland session, where the Home Manager configuration of any user (`mathew`, `openclaw-npm`, the Linux part of `DooNeGo`) is tried without the owner's `switch` and without touching the owner's stream. It has no configuration of its own. The system side is `system-config/nixos/testuser.nix` (option `testuser.enable`).

## Account and session

- Groups: `video` only, no `input` (the headless session needs no physical input devices; raw `input` would read the owner's keyboard). No password: login is by ssh key of `openclaw-npm`; hyprlock is unlocked with `pkill -USR1 hyprlock`. No linger: the user manager lives while the session runs.
- `hyprland-headless-testuser.service` is `hyprland-headless-mathew` with the same environment (`HYPRLAND_START_LOCKED`, `LIBSEAT_BACKEND=noop`, `AQ_NO_KMS_REQUIREMENT`). A polkit rule lets `openclaw-npm` (and only it) start, stop and restart this unit.
- The sessions exclude each other: starting mathew's stream or Steam session stops the test session (`Conflicts=`), and the test unit refuses to start (`ExecStartPre`) while either runs.

## Applying a configuration

`scripts/testuser-switch.sh [--with MODULE]... TARGET` builds `homeConfigurations.TARGET` from `home-config/TARGET` with its own flake and lock, changes only `home.username` and `home.homeDirectory` to `testuser` (`extendModules`), and runs `activate` over ssh. There is no Home Manager profile, so no generations to roll back to: stop the session and apply again. `--build-only` only builds; the script refuses to activate while the session runs (activation restarts its units and can crash it), `--force` overrides.

Extra test modules for one run live in `home-config/testuser/modules/` and are passed with `--with`:

| Module | Purpose |
|---|---|
| `fake-sunshine.nix` | stands in for Sunshine (it runs for mathew only): a unit ordered `After=hyprlock-initial.service`, to check the start order |

## Testing a session change

1. `scripts/testuser-switch.sh --with home-config/testuser/modules/fake-sunshine.nix mathew` with the session stopped.
2. `systemctl restart hyprland-headless-testuser` (the agent may, via polkit).
3. Over ssh take the newest instance in `$XDG_RUNTIME_DIR/hypr/` (directory name `<hash>_<epoch>_<nsec>`), set `HYPRLAND_INSTANCE_SIGNATURE` and `WAYLAND_DISPLAY`, then `hyprctl layers -j`, `hyprctl monitors -j`, `grim -t ppm -o HEADLESS-1` and `pkill -USR1 hyprlock`.
4. A flat frame (a lock or crossfade glitch) has a pixel standard deviation below about 6; mean brightness cannot tell it (a blur keeps the mean).
5. Stop the session afterwards.

The result holds for the compositor output only: it has no Sunshine and no Moonlight client, so the owner's stream is the last check.

## Owner

The first `switch` after a rename creates the account; an old account and its home are removed by hand (`userdel`, `rm -rf /home/<old>`).
