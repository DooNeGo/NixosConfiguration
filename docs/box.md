# Test box

For a change that the owner's `switch` cannot check safely or often enough (the order of the session, hyprlock, a user unit, a Home Manager module of any user), the agent runs the Home Manager configuration in a NixOS container: rootless podman under `openclaw-npm`, no `sudo`, no action of the owner per run. The first check of every change is a build (`home-manager build`, `nixos-rebuild build`); the box comes when a build is not enough. The owner's stream is the last check.

`scripts/box.sh --help` lists the commands; the system of the container is `system-config/box/` (its own flake and lock, `scripts/flake-update.sh box`).

## How it works

- `box.sh up` builds the container system, replaces a running container (its home is lost) and runs the new one with `podman run --rootfs --systemd=always` from `systemd-run --user`, with no network. The container is a real NixOS: systemd is PID 1, Hyprland with UWSM and hyprlock as on the host.
- The host `/nix/store` is mounted read-only and the nix daemon socket is mounted too, so the container uses the packages of the host store and builds nothing itself: `box.sh switch TARGET` builds `homeConfigurations.TARGET` on the host (target flake and lock as they are, only `home.username` and `home.homeDirectory` change to the container root) and runs its `activate` inside.
- The GPU is the host's NVIDIA: `/dev/dri/card0` and `renderD128`, the `/dev/nvidia*` devices and `/run/opengl-driver`. Hyprland needs `card0` even for a headless output; the host group `video` reaches it through `--group-add keep-groups`, which is why `openclaw-npm` is in `video`.
- `box.sh up`, `switch` and `session start|restart` refuse while `hyprland-headless-mathew` or `steam-bigpicture-mathew` runs: two sessions on one GPU.
- The builds are kept as out links in `~/.local/state/box/roots`: they are the GC roots of the running container (`nh clean` would otherwise remove its system). `box.sh down` removes the container and its root; the state directory stays.
- The user manager needs no ssh session: `openclaw-npm` has linger. A user manager started before `openclaw-npm` joined `video` does not have the group: after the `switch` that adds it, the owner restarts it (`sudo systemctl restart user@<uid>.service`) (otherwise Hyprland dies with `CBackend::create() failed!`).

## Session in the box

- The session runs as the container root, which is `openclaw-npm` on the host. A container user cannot open `card0`: the kept group `video` is unmapped for it, and `user@N` drops it. So `user@0.service` has a drop-in without `User=` and `PAMName=`, and Hyprland starts with `--i-am-really-stupid`.
- The unit `hyprland-headless-root` mirrors `hyprland-headless-mathew` (`LIBSEAT_BACKEND=noop`, `AQ_NO_KMS_REQUIREMENT`, `HYPRLAND_START_LOCKED`), so `hyprland/session.lua` creates `HEADLESS-1` as it does for the stream.
- The home directory and `/tmp` of the container are lost with it: run `switch` after every `up`. Restarting the session only needs `box.sh session`.
- `box.sh shot [COUNT [DELAY]]` takes grim frames of `HEADLESS-1` into `~/.local/state/box/shots` (the frames of the previous call are removed) and prints the pixel standard deviation of each. The desktop is drawn some seconds after `session` returns, so the first frames after a start are empty (deviation below 6): look at frames once `hyprlock-initial` is active. After that a flat frame (a lock or crossfade glitch) has a deviation below about 6; the mean brightness cannot tell it, because a blur keeps the mean.

## Testing a session change

1. `scripts/box.sh up`, then `scripts/box.sh switch mathew`. Sunshine does not start in the box (its unit has `ConditionUser=mathew`); its order after `hyprlock-initial.service` is read from the configuration: `nix eval --json ./system-config/nixos#nixosConfigurations.nixos.config.systemd.user.services.sunshine.after`.
2. `scripts/box.sh session restart`.
3. `scripts/box.sh exec 'systemctl --user show -p ActiveEnterTimestamp hyprpaper waybar hyprlock-initial'` for the order of starts; `scripts/box.sh shot 3`, then `scripts/box.sh exec pkill -USR1 hyprlock` and `scripts/box.sh shot 25 0.1` for the unlock.
4. `scripts/box.sh down`.

The result holds for the compositor output only.

## Limits

- Not tested: `switch-to-configuration` inside a live container (the container system is replaced by `up`), Sunshine and NVENC in the container.
- The box does not isolate the GPU driver: the container has the host `/dev/nvidia*` and `card0`. A rootless container confines the files and the processes to the rights of `openclaw-npm`, nothing more.
- Rootless podman needs the subuid range of the user (NixOS gives one to every normal user) and a podman built from nixpkgs; `box.sh` takes it from the box flake, the host has none.
