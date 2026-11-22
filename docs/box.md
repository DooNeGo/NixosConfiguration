# Test box

For a change that the owner's `switch` cannot check safely or often enough (the order of the session, hyprlock, a user unit, a Home Manager module), the agent runs the real system and home configurations in a NixOS container (rootless podman under `openclaw-npm`) or in a VM (QEMU with KVM): no `sudo`, no action of the owner per run. The first check of every change is a build (`home-manager build`, `nixos-rebuild build`); the box comes when a build is not enough. The owner's stream is the last check.

The box is a tool, not a configuration: `tools/box/` belongs to no system and no home. It takes flakes of this repository as they are (each with its own lock) and puts small override layers on top. `tools/box/box --help` lists the commands.

## Container or VM

The default is the container (`--backend container`): it uses the host NVIDIA and kernel and needs no KVM. Use the VM (`--backend vm`) when there is at least one reason for it: the check depends on a whole boot with a kernel, on the real SDDM, on udev or sysfs, or on mounts. Everything else stays in the container.

| | container | VM |
|---|---|---|
| system | the real configuration plus `backends/container` | the real configuration plus `backends/vm` (`qemu-vm.nix`) |
| session user | the user of the home (`mathew`); its user manager is started by the container root (see Session user in the container) | the user of the home, a real login manager |
| GPU | the host NVIDIA through CDI | a virtual one (virtio-gpu with OpenGL on the host render node), not NVIDIA |
| display manager | SDDM stub | the real SDDM |
| `box test --system nixos --home mathew` | about 32 s | about 45 s (medians of 3 runs, 2026-11-22; `box up` takes about 13 s and 23 s) |
| memory | shared host kernel | 3 GB guest, about 1.7 GB resident on the host |

Both backends use the same layers, fixtures and checks; one name is one backend (`box up --backend vm --name x` replaces a container `x`).

## How it works

- `box up --system nixos --home mathew` generates a flake in `~/.local/state/box/<name>/flake` that has the targets as inputs (`NAME` means `system-config/NAME#NAME` and `home-config/NAME#NAME`; `PATH#ATTR` names any flake inside the repository) and builds it without `--impure`. The system is the real `nixosConfigurations.nixos` extended with the layers; the home is the real `homeConfigurations.mathew` with `home.username = "root"` and `home.homeDirectory = "/root"`.
- The container is `podman run --rootfs --systemd=always` started by `systemd-run --user`, with no network: a real NixOS with systemd as PID 1. The host `/nix/store` is mounted read-only and the nix daemon socket too, so the container uses the packages of the host store and builds nothing.
- `box build` only builds (into `roots/build-*`, so it never replaces the roots of a running instance). `box test` first reads every layer (an unknown fixture, a cycle, no checks at all are errors before anything is built), then runs `up`, the checks and `down` (`--keep` leaves it running, `--timings` also prints the time of `up`, of each fixture and of the whole run (each check always prints its own), `--tests NAME...` runs the checks of those names or shell patterns (`--tests 'session-*' unlock-frame`, or comma-separated; a name that matches nothing is an error); an interrupted `test` removes its instance). The unit tests of the tool: `python3 -m unittest discover -s tools/box/tests -t tools/box`.
- The GPU is passed only when a layer asks for it with a file `gpu` in its directory (`systems/nixos/gpu`); a system without one runs without the GPU and the `video` check. In a container it is the host's NVIDIA through the NVIDIA container toolkit: the host enables `hardware.nvidia-container-toolkit.enable`, a boot service writes the CDI spec to `/var/run/cdi`, and `box up` passes `--device nvidia.com/gpu=all` (the `/dev/dri` and `/dev/nvidia*` nodes, the driver files, `/run/opengl-driver`, `nvidia-smi`). `box up` fails with a message when the spec is missing. The spec alone does not open `card0` to the container root: its `additionalGids` is the group 26 of the user namespace, not the host's `video` (tried 2026-11-20 with podman 6.1.4: `card0` opens read-write only with `--group-add keep-groups`; rerun `box test` after a podman update). Hyprland needs `card0` even for a headless output, so `keep-groups` stays and `openclaw-npm` is in `video`. A user manager started before that needs `sudo systemctl restart user@<uid>.service` from the owner (otherwise Hyprland dies with `CBackend::create() failed!`); `box up` checks it (only for a layer with `gpu`).
- The box runs next to the owner's stream session (tried 2026-11-19, the stream was not affected): the container opens the same `card0`, which is not DRM master for the headless output. The render and nvidia devices are world-accessible, `card0` only for the group `video`. The spec is regenerated when the host switches: a running instance keeps the one it started with. VRAM and NVENC are shared, so a long test may load a stream.
- Builds are kept as out links in `~/.local/state/box/<name>/roots`: they are the GC roots of the running container (`nh clean` would otherwise remove its system). `box down` removes the container and its rootfs; the out links in `roots/` stay until `<state>/<name>` is deleted, and their store paths are not collected meanwhile.
- One home per instance.

## Layers

Applied in this order, each only when it exists, found by the attribute name of the target. In a layer directory `module.nix` applies to both backends and `<backend>.nix` (`container.nix`, `vm.nix`) to that one only.

1. `tools/box/backends/lib.sh` (`box_user`, shared) and `tools/box/backends/<backend>/module.nix`: always. `container`: `isContainer`, what a rootless container cannot run (the nix daemon, nscd, dbus-broker, mounts), `nix` for the home activation. `vm`: `qemu-vm.nix` (root on tmpfs, 3 GB, 4 vCPU, the host store over virtiofs, no way out to the network), stubs for the file systems of the real machine, sshd on vsock with the key from a systemd credential.
2. `tools/box/systems/<attr>/`: overrides of that system (NixOS modules). `nixos/module.nix`: the tools `grim`, `jq`, `imagemagick` for the checks, and what is not tested or needs what the box lacks off through its `enable` option (cups, Tailscale, murmur, smartd, the XDG portals; btrbk through its emptied `instances`) or `disabledUnits` (the sing-box credential helpers `-fetch` and `-awg-prepare`, the AmneziaWG exit node; the `sing-box-<name>` units stay and restart in a loop for lack of credentials). `container.nix`: resolved, the firewall and nftables off, the SDDM stub, openrazer and rtkit off (the container lacks their capabilities), the drop-in of `user@.service`. `vm.nix`: the NVIDIA container toolkit and services and the btrfs reclaim off, the Mesa EGL vendor for the session.
3. `tools/box/homes/<attr>/`: overrides of that home (Home Manager modules). `mathew/module.nix`: the polkit agent off (the container has no polkit daemon, the headless session of the VM no logind session for it). `mathew/vm.nix`: the NVIDIA session variables replaced by Mesa's, the virtual display `Virtual-1` disabled (SDDM holds its DRM master, as it does that of `DP-2` on the real machine).
4. `--system-module FILE` (NixOS) and `--home-module FILE` (Home Manager): one-off layers on top, repeatable. Only the file itself is copied into the generated flake: it cannot import a sibling file by a relative path.

A unit of the real system that fails in the box gets one of three answers. Do we need to test it now? If yes, decide what exactly is tested and how: build its environment (a test secret, a network), or override its settings or sub-units for the box in a way that keeps what the unit and the configuration do (`SuccessExitStatus`, a stub of a helper). If not, and no unit orders after it, `lib.mkForce` its `enable` option (or its parent's: `services.<x>.enable`) off in the layer. If other units order after it, replace its package with a stub from `tools/box/stubs/`: the unit stays and the order is real. A fix that needs more privileges for the container (a capability, a device, a changed security profile) is not made: the unit is switched off, or the owner decides. A stub says in its header what it does not test. Tailscale, sing-box and agenix secrets are not tested yet.

## Session user in the container

This section is about the container backend; the VM runs the session as the user of the home with a real login.

The session runs as the user of the home (`mathew`), like on the real machine. The obstacle is `card0`: it is `root:video 0660` on the host, and a container user reaches it only through the supplementary group `video` that `--group-add keep-groups` keeps; `video` of the host is not mapped into the user namespace, and `User=` makes systemd call `setgroups`, which drops it. So `container.nix` gives `user@.service` a drop-in: the user manager starts as the container root and `setpriv --reuid --regid --keep-groups` changes its uid and gid (the script reads the gid with `id -g`, so no id is written in the layer) without touching the groups. The script first hands the cgroup of the unit to that user (`DelegateSubgroup=` is cleared for the same reason). Everything below `user@N` then runs as `mathew` with the group, so Hyprland opens `card0` and Sunshine starts (`ConditionUser=mathew` holds). The home activation first lets `box_session_up` (`backends/lib.sh`) enable linger for the user of the home and wait for its bus, so the user manager outlives the session unit. Commands of the layers run as the container root; `box_user` (`backends/lib.sh`) runs one as the session user with its bus.

Tried and dropped (2026-11-21, podman 6.1.4): `seatd` (setting DRM master needs `CAP_SYS_ADMIN`); `--userns=keep-id` (it boots, but `acpid`, `avahi` and `usbmuxd` fail, cause not examined); a kept group with `User=` (`setgroups` drops it); `--cap-add SYS_ADMIN` and `--device /dev/fuse` for the document portal (privileges stay off, the portals are not tested: `xdg.portal.enable` is off in the layer).

Not tested because of this: the order after the real SDDM (`display-manager.service` is a stub), the real sysfs settings (`boot.kernel.sysfs` is empty), the portals (file chooser, screen sharing) and rtkit.

## The VM

`box up --backend vm` builds `config.system.build.vm` of the generated flake and runs its `bin/run-nixos-vm` in a transient user unit `box-<name>`. The guest has no network (QEMU user networking with `restrict=on`). The host reaches it with ssh over AF_VSOCK (`/dev/vhost-vsock` is world-writable here): `boxlib/vsock_proxy.py` is the `ProxyCommand`, the key is made at every start and reaches the guest as the systemd credential `ssh.authorized_keys.root` (QEMU `-smbios type=11`). The CID comes from the name of the instance. Commands run as the guest root; the user of the home is `BOX_USER`, and `box_user CMD` (`backends/lib.sh`, the same in both backends) runs `CMD` as that user with its runtime directory.

The home is applied by `activate` as its own user; its closure goes into the guest through `virtualisation.additionalPaths`. The user of the home comes from `lib.username` of the generated flake. `<state>/<name>/out` is a writable virtiofs share, `/out` in the guest. `console.log` of the instance is the serial console: `box up` prints its tail when the guest does not come up.

The virtual GPU is `virtio-vga-gl` with `egl-headless` on the first `/dev/dri/renderD*` of the host, so it needs no root and no group. It is not NVIDIA: the layer of the VM replaces the NVIDIA EGL vendor and the NVIDIA session variables, and checks of the rendered desktop pass on Mesa's renderer. Whether it is virgl or the software renderer was not examined.

Not tested in the VM: the NVIDIA driver, NVENC, Sunshine, the real mounts (`/backup`, `/mnt/btrfs-top` are tmpfs stubs, the btrfs reclaim units are off), the real sysfs (`boot.kernel.sysfs` is empty), Tailscale, sing-box and the agenix secrets. QEMU runs with KVM and keeps its memory resident, so keep the number of parallel VMs low (a VM and a container run side by side without trouble).

## Instances

The name is the system and the home joined by `-` (`nixos-mathew`), or `--name`. The unit (and the container) is `box-<name>`, state is `~/.local/state/box/<name>/` (rootfs or `run`, frames in `out`, GC roots, lock, metadata with the backend). The lock is per instance: different names run side by side; a second `up`, `down` or `build` of a name that is busy fails at once, and an `up` after the previous one finished replaces the container. `box list` shows them; a command without `--name` takes the only running instance and uses the backend it was started with.

## Fixtures and checks

A layer holds `fixtures/<name>/{setup,teardown,requires}` and `checks/<name>.sh`, run inside the system as its root after the `lib.sh` of every layer. A fixture is a state a check needs (`session`: the session unit started; `desktop-ready`: `hyprlock-initial` active, requires `session`); the layer owns how it is made and removed. A check names what it needs in `# requires: a, b (shared)` lines and the backends it runs on in a line `# backends: container, vm`; without that line it runs on every backend, so a check that depends on one of them says so. A check whose fixtures are all `(shared)` shares them with the other such checks and they stay up until the last of them; every other check (a mix of shared and plain references too) gets its fixtures set up fresh and torn down right after it, so the order of checks does not matter. A fixture whose requirement failed is not set up, and the checks that need it fail with that reason. A check passes when it exits 0.

| Check | Layer | What it asserts |
|---|---|---|
| `no-failed-units` | `systems/nixos` | no unit failed after boot |
| `no-failed-user-units` | `homes/mathew` | no user unit of the desktop session failed |
| `session-order` | `homes/mathew` | `hyprlock-initial` started after `hyprpaper` and `waybar` |
| `unlock-frame` | `homes/mathew` | no flat frame after the unlock |
| `session-frame` | `systems/nixos` | the session draws: a frame with a deviation of 6 or more within 60 s |

Commands of the session user in a script go through `box_user`. `box exec 'box_shot COUNT DELAY'` takes grim frames of `HEADLESS-1` into `<state>/<name>/out` (replacing the previous ones; a frame grim did not write is an error) and prints the pixel standard deviation of each. The desktop is drawn some seconds after the session starts, so the first frames are empty (deviation below 6): look at frames once `hyprlock-initial` is active. A flat frame (a lock or crossfade glitch) has a deviation below about 6; the mean brightness cannot tell it, because a blur keeps the mean. `box fixture session setup|teardown|restart` runs a fixture of the layers by hand. `box exec` runs a command in the container with the `lib.sh` helpers of the layers (`box_shot`, `wait_output`) defined.

## Limits

- Not tested: `switch-to-configuration` inside a live container (the container system is replaced by `up`), the capture and NVENC of Sunshine (the service starts in the container, no check streams).
- The box does not isolate the GPU driver: the container has the host `/dev/nvidia*` and `card0`; the CDI spec also gives it the NVENC and NVML libraries, which no check uses yet. A rootless container confines the files and the processes to the rights of `openclaw-npm`, nothing more.
- Rootless podman needs the subuid range of the user (NixOS gives one to every normal user) and a podman built from nixpkgs; `box` takes it from `tools/box/flake.nix`, the host has none.
