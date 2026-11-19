# Test box

For a change that the owner's `switch` cannot check safely or often enough (the order of the session, hyprlock, a user unit, a Home Manager module), the agent runs the real system and home configurations in a NixOS container: rootless podman under `openclaw-npm`, no `sudo`, no action of the owner per run. The first check of every change is a build (`home-manager build`, `nixos-rebuild build`); the box comes when a build is not enough. The owner's stream is the last check.

The box is a tool, not a configuration: `tools/box/` belongs to no system and no home. It takes flakes of this repository as they are (each with its own lock) and puts small override layers on top. `tools/box/box --help` lists the commands.

## How it works

- `box up --system nixos --home mathew` generates a flake in `~/.local/state/box/<name>/flake` that has the targets as inputs (`NAME` means `system-config/NAME#NAME` and `home-config/NAME#NAME`; `PATH#ATTR` names any flake inside the repository) and builds it without `--impure`. The system is the real `nixosConfigurations.nixos` extended with the layers; the home is the real `homeConfigurations.mathew` with `home.username = "root"` and `home.homeDirectory = "/root"`.
- The container is `podman run --rootfs --systemd=always` started by `systemd-run --user`, with no network: a real NixOS with systemd as PID 1. The host `/nix/store` is mounted read-only and the nix daemon socket too, so the container uses the packages of the host store and builds nothing.
- `box build` only builds (into `roots/build-*`, so it never replaces the roots of a running instance). `box test` first reads every layer (an unknown fixture, a cycle, no checks at all are errors before anything is built), then runs `up`, the checks and `down` (`--keep` leaves it running, `--only NAME` runs one check; an interrupted `test` removes its instance). The unit tests of the tool: `python3 -m unittest discover -s tools/box/tests -t tools/box`.
- The GPU is passed only when a layer asks for it with a file `gpu` in its directory (`systems/nixos/gpu`); a system without one runs without the devices, the driver mount and the `video` check. It is the host's NVIDIA: `/dev/dri/card0` and `renderD128`, the `/dev/nvidia*` devices and `/run/opengl-driver`. Hyprland needs `card0` even for a headless output; the host group `video` reaches it through `--group-add keep-groups`, which is why `openclaw-npm` is in `video`. A user manager started before that needs `sudo systemctl restart user@<uid>.service` from the owner (otherwise Hyprland dies with `CBackend::create() failed!`); `box up` checks it (only for a layer with `gpu`).
- The box runs next to the owner's stream session (tried 2026-11-19, the stream was not affected): the container opens the same `card0`, which is not DRM master for the headless output. The render and nvidia devices are world-accessible, `card0` only for the group `video`. VRAM and NVENC are shared, so a long test may load a stream.
- Builds are kept as out links in `~/.local/state/box/<name>/roots`: they are the GC roots of the running container (`nh clean` would otherwise remove its system). `box down` removes the container and its rootfs; the out links in `roots/` stay until `<state>/<name>` is deleted, and their store paths are not collected meanwhile.
- One home per instance: every home runs as the container root and would overwrite the other.

## Layers

Applied in this order, each only when it exists, found by the attribute name of the target:

1. `tools/box/container.nix`: always. `isContainer`, what a rootless container cannot run (the nix daemon, nscd, dbus-broker, mounts), the drop-in of `user@0`, `nix` for the home activation.
2. `tools/box/systems/<attr>/module.nix`: overrides of that system (a NixOS module). `nixos`: the tools `grim`, `jq`, `imagemagick` for the checks, resolved off, the SDDM stub, the session unit as root (through a Hyprland package that adds the root flag), the units that need what the container lacks off.
3. `tools/box/homes/<attr>/module.nix`: overrides of that home (a Home Manager module). `mathew`: the polkit agent off (polkit does not run in the container).
4. `--system-module FILE` (NixOS) and `--home-module FILE` (Home Manager): one-off layers on top, repeatable. Only the file itself is copied into the generated flake: it cannot import a sibling file by a relative path.

A unit of the real system that fails in the container gets one of three answers. Do we need to test it now? If yes, build its environment (a test secret, a network). If not, and no unit orders after it, `lib.mkForce` it off in the layer. If other units order after it, replace its package with a stub from `tools/box/stubs/`: the unit stays and the order is real. A stub says in its header what it does not test. Tailscale, sing-box and agenix secrets are not tested yet.

## Session as the container root

The session runs as the container root, which is `openclaw-npm` on the host. A container user cannot open `card0`: the kept group `video` is unmapped for it, and `user@N` drops it. So `systems/nixos/module.nix` runs `hyprland-headless-mathew` with `User=root`, and `container.nix` gives `user@0.service` a drop-in without `User=` and `PAMName=`. Hyprland refuses to run as root without `--i-am-really-stupid`: the layer swaps `programs.hyprland.package` for a copy whose `hyprland.desktop` has `Exec=start-hyprland -- --i-am-really-stupid`. The unit keeps its own `ExecStart` (`uwsm start -e -D Hyprland hyprland.desktop`), so a change of that line is tested.

Not tested because of this: `User=mathew`, the order after the real SDDM (`display-manager.service` is a stub), the real sysfs settings (`boot.kernel.sysfs` is empty), `ConditionUser=mathew` units (Sunshine does not start in the box; its order after `hyprlock-initial.service` is read from the configuration: `nix eval --json ./system-config/nixos#nixosConfigurations.nixos.config.systemd.user.services.sunshine.after`).

## Instances

The name is the system and the home joined by `-` (`nixos-mathew`), or `--name`. Unit and container are `box-<name>`, state is `~/.local/state/box/<name>/` (rootfs, frames in `out`, GC roots, lock). The lock is per instance: different names run side by side; a second `up`, `down` or `build` of a name that is busy fails at once, and an `up` after the previous one finished replaces the container. `box list` shows them; a command without `--name` takes the only running instance.

## Fixtures and checks

A layer holds `fixtures/<name>/{setup,teardown,requires}` and `checks/<name>.sh`, run inside the container as its root after the `lib.sh` of every layer. A fixture is a state a check needs (`session`: the session unit started; `desktop-ready`: `hyprlock-initial` active, requires `session`); the layer owns how it is made and removed. A check names what it needs in `# requires: a, b (shared)` lines. A check whose fixtures are all `(shared)` shares them with the other such checks and they stay up until the last of them; every other check (a mix of shared and plain references too) gets its fixtures set up fresh and torn down right after it, so the order of checks does not matter. A fixture whose requirement failed is not set up, and the checks that need it fail with that reason. A check passes when it exits 0.

| Check | Layer | What it asserts |
|---|---|---|
| `no-failed-units` | `systems/nixos` | no unit failed after boot |
| `no-failed-user-units` | `homes/mathew` | no user unit of the desktop session failed |
| `session-order` | `homes/mathew` | `hyprlock-initial` started after `hyprpaper` and `waybar` |
| `unlock-frame` | `homes/mathew` | no flat frame after the unlock |

`box exec 'box_shot COUNT DELAY'` takes grim frames of `HEADLESS-1` into `<state>/<name>/out` (replacing the previous ones; a frame grim did not write is an error) and prints the pixel standard deviation of each. The desktop is drawn some seconds after the session starts, so the first frames are empty (deviation below 6): look at frames once `hyprlock-initial` is active. A flat frame (a lock or crossfade glitch) has a deviation below about 6; the mean brightness cannot tell it, because a blur keeps the mean. `box fixture session setup|teardown|restart` runs a fixture of the layers by hand. `box exec` runs a command in the container with the `lib.sh` helpers of the layers (`box_shot`, `wait_output`) defined.

## Limits

- Not tested: `switch-to-configuration` inside a live container (the container system is replaced by `up`), Sunshine and NVENC in the container.
- The box does not isolate the GPU driver: the container has the host `/dev/nvidia*` and `card0`. A rootless container confines the files and the processes to the rights of `openclaw-npm`, nothing more.
- Rootless podman needs the subuid range of the user (NixOS gives one to every normal user) and a podman built from nixpkgs; `box` takes it from `tools/box/flake.nix`, the host has none.
