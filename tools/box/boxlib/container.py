"""The container backend: rootless podman runs the system as a container with systemd as PID 1."""

import grp
import json
import os
from pathlib import Path

from .instance import BoxError, Host, Instance, sh

# The NVIDIA container toolkit (hardware.nvidia-container-toolkit) writes the CDI spec of the host GPU: the device
# nodes, the driver files and /run/opengl-driver come from it, so the box lists none of them.
CDI_DIRS = ("/etc/cdi", "/var/run/cdi")
CDI_KIND = "nvidia.com/gpu"
CDI_DEVICE = f"{CDI_KIND}=all"


class Podman:
    """The podman of this repository's flake (the host needs none), set up on the first use."""

    def __init__(self, host: Host):
        self.host = host
        self.ready_ = False

    def setup(self) -> None:
        if self.ready_:
            return
        (self.host.state / "roots").mkdir(parents=True, exist_ok=True)
        # An out link per build is a GC root: the running containers use these store paths.
        built = sh(
            [
                "nix",
                "build",
                "--option",
                "warn-dirty",
                "false",
                "--out-link",
                str(self.host.state / "roots/podman"),
                "--print-out-paths",
                f"{self.host.repo}/tools/box#packages.x86_64-linux.podman",
            ],
            capture=True,
            stdout_only=True,
        ).stdout.strip()
        runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
        conf = (
            "[storage]\n"
            # overlay needs privileges a rootless user lacks, and containers start from a rootfs directory
            'driver = "vfs"\n'
            f'graphroot = "{self.host.state}/storage"\n'
            f'runroot = "{runtime}/box"\n'
        )
        tmp = self.host.state / f"storage.conf.tmp.{os.getpid()}"
        tmp.write_text(conf)
        os.replace(tmp, self.host.state / "storage.conf")
        # newuidmap and newgidmap are the setuid wrappers of the host.
        self.host.env["PATH"] = f"{built}/bin:/run/wrappers/bin:{self.host.env['PATH']}"
        self.host.env["CONTAINERS_STORAGE_CONF"] = str(self.host.state / "storage.conf")
        self.ready_ = True

    def __call__(
        self, *args: str, check: bool = True, capture: bool = False, stdin: bool = False, stdout_only: bool = False
    ):
        self.setup()
        return sh(
            ["podman", *args], env=self.host.env, check=check, capture=capture, stdin=stdin, stdout_only=stdout_only
        )


class ContainerInstance(Instance):
    backend = "container"

    def __init__(self, host, name: str, user: str | None = None):
        super().__init__(host, name, user)
        self.container = self.unit
        self.podman = Podman(host)

    def running(self) -> bool:
        if self.podman("container", "exists", self.container, check=False).returncode != 0:
            return False
        inspect = self.podman("inspect", "-f", "{{.State.Running}}", self.container, capture=True, stdout_only=True)
        return inspect.stdout.strip() == "true"

    def check_host(self, gpu: bool) -> None:
        if gpu:
            require_cdi()
            require_video()

    def inner(
        self, script: str, *, stdin: bool = False, capture: bool = False, check: bool = True, stdout_only: bool = False
    ):
        # The environment of the container root; the session user's commands go through box_user.
        args = ["exec", *(["-i"] if stdin else []), "-e", "USER=root", "-e", "HOME=/root", "-e", "NIX_REMOTE=daemon"]
        args += [self.container, "/run/current-system/sw/bin/bash", "-lc", script]
        return self.podman(*args, capture=capture, check=check, stdin=stdin, stdout_only=stdout_only)

    def remove_container(self) -> None:
        # SIGTERM to `podman run` is a signal that systemd inside ignores: the unit would wait its 90 s stop timeout.
        # `podman stop` sends the stop signal of systemd containers, which powers it off.
        self.podman("stop", "-t", "10", self.container, check=False, capture=True)
        self.stop_unit()
        self.podman("rm", "-f", self.container, check=False, capture=True)

    def remove_rootfs(self) -> None:
        # Files of container users belong to subuids: only the user namespace of podman may remove them.
        self.podman("unshare", "rm", "-rf", str(self.dir / "rootfs"), check=False)

    def start(self, top: Path, gpu: bool) -> None:
        self.remove_container()
        self.reset_unit()
        self.remove_rootfs()
        (self.dir / "rootfs").mkdir(parents=True, exist_ok=True)
        self.prepare_out()
        cmd = [
            "systemd-run",
            "--user",
            "--quiet",
            f"--unit={self.container}",
            "--setenv=PATH",
            "--setenv=CONTAINERS_STORAGE_CONF",
            "podman",
            "run",
            "--rm",
            "--name",
            self.container,
            "--rootfs",
            "--network=none",
            "--systemd=always",
            *gpu_args(gpu),
            "-v",
            "/nix/store:/nix/store:ro",
            "-v",
            # for the nix commands of the Home Manager activation
            "/nix/var/nix/daemon-socket:/nix/var/nix/daemon-socket",
            "-v",
            f"{self.dir}/out:/out",
            "--tmpfs",
            "/run/wrappers:rw,exec,suid,mode=755",
            str(self.dir / "rootfs"),
            f"{top}/init",
        ]
        self.podman.setup()
        sh(cmd, env=self.host.env, what="systemd-run of the container")

    def ready(self) -> bool:
        return self.running()

    def down(self) -> None:
        self.remove_container()
        self.remove_rootfs()


def gpu_args(gpu: bool) -> list[str]:
    """The podman arguments of the host GPU. The CDI spec alone is not enough: its additionalGids names the group
    `video` of the user namespace, not the host's, so /dev/dri/card0 (which Hyprland needs even for a headless
    output) stays closed; keep-groups passes the groups of the user manager, and `require_video` checks them."""
    return ["--device", CDI_DEVICE, "--group-add", "keep-groups"] if gpu else []


def cdi_has_gpu(dirs: tuple[str, ...] = CDI_DIRS) -> bool:
    """True when a CDI spec in `dirs` defines the device `all` of the NVIDIA GPU kind."""
    for directory in dirs:
        for spec in sorted(Path(directory).glob("*.json")):
            try:
                data = json.loads(spec.read_text())
            except (OSError, ValueError):
                continue
            if data.get("kind") == CDI_KIND and any(d.get("name") == "all" for d in data.get("devices", [])):
                return True
    return False


def require_cdi() -> None:
    if not cdi_has_gpu():
        raise BoxError(
            f"no CDI spec for {CDI_DEVICE} in {' or '.join(CDI_DIRS)}; the host needs "
            "hardware.nvidia-container-toolkit.enable and a switch, then "
            "`systemctl status nvidia-container-toolkit-cdi-generator` shows why the spec is missing"
        )


def require_video() -> None:
    """A user manager started before openclaw-npm joined `video` lacks the group, and Hyprland fails unhelpfully."""
    if not Path("/dev/dri/card0").exists():
        return
    try:
        gid = grp.getgrnam("video").gr_gid
    except KeyError:
        raise BoxError("the host has no group video") from None
    # The unit of the user manager: `pgrep systemd` would also match the systemd of a running container.
    shown = sh(
        ["systemctl", "show", f"user@{os.getuid()}.service", "-p", "MainPID", "--value"],
        capture=True,
        stdout_only=True,
        check=False,
    )
    pid = shown.stdout.strip()
    if not pid.isdigit() or pid == "0":
        raise BoxError("no systemd user manager for this user; enable linger or log in")
    groups: list[str] = []
    for line in Path(f"/proc/{pid}/status").read_text().splitlines():
        if line.startswith("Groups:"):
            groups = line.split()[1:]
    if str(gid) not in groups:
        raise BoxError(
            f"the user manager has no group video; the owner restarts it (systemctl restart user@{os.getuid()}.service)"
        )
