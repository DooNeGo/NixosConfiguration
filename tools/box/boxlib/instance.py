"""Host side of a box instance: rootless podman, the container of one system and the commands run inside it."""

import fcntl
import grp
import json
import os
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

from .layers import Layer

# The environment of the user session of the container root, for everything run inside.
INNER_ENV = {
    "USER": "root",
    "HOME": "/root",
    "XDG_RUNTIME_DIR": "/run/user/0",
    "DBUS_SESSION_BUS_ADDRESS": "unix:path=/run/user/0/bus",
    "NIX_REMOTE": "daemon",
}
DEVICES = [
    "/dev/dri/card0",
    "/dev/dri/renderD128",
    "/dev/nvidiactl",
    "/dev/nvidia0",
    "/dev/nvidia-modeset",
    "/dev/nvidia-uvm",
    "/dev/nvidia-uvm-tools",
]
BOOT_WAIT_SECONDS = 120


class BoxError(Exception):
    """A runtime failure: exit status 1."""


def sh(
    cmd: list[str],
    *,
    env: dict[str, str] | None = None,
    capture: bool = False,
    check: bool = True,
    stdin: bool = False,
    stdout_only: bool = False,
    what: str | None = None,
) -> subprocess.CompletedProcess:
    """`what` names the step in the error. capture keeps stdout and stderr together; stdout_only leaves stderr alone."""
    result = subprocess.run(
        cmd,
        env=env,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.STDOUT if capture and not stdout_only else None,
        stdin=None if stdin else subprocess.DEVNULL,
        check=False,
    )
    if check and result.returncode != 0:
        raise BoxError(f"{what or ' '.join(cmd[:3])} failed with status {result.returncode}")
    return result


@dataclass
class Host:
    repo: Path
    state: Path
    env: dict[str, str]

    @classmethod
    def create(cls, repo: Path) -> "Host":
        base = os.environ.get("XDG_STATE_HOME") or str(Path.home() / ".local/state")
        return cls(repo, Path(base) / "box", dict(os.environ))

    def setup_podman(self) -> None:
        (self.state / "roots").mkdir(parents=True, exist_ok=True)
        # An out link per build is a GC root: the running containers use these store paths.
        built = sh(
            [
                "nix",
                "build",
                "--option",
                "warn-dirty",
                "false",
                "--out-link",
                str(self.state / "roots/podman"),
                "--print-out-paths",
                f"{self.repo}/tools/box#packages.x86_64-linux.podman",
            ],
            capture=True,
            stdout_only=True,
        ).stdout.strip()
        runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
        conf = (
            "[storage]\n"
            # overlay needs privileges a rootless user lacks, and containers start from a rootfs directory
            'driver = "vfs"\n'
            f'graphroot = "{self.state}/storage"\n'
            f'runroot = "{runtime}/box"\n'
        )
        tmp = self.state / f"storage.conf.tmp.{os.getpid()}"
        tmp.write_text(conf)
        os.replace(tmp, self.state / "storage.conf")
        # newuidmap and newgidmap are the setuid wrappers of the host.
        self.env["PATH"] = f"{built}/bin:/run/wrappers/bin:{self.env['PATH']}"
        self.env["CONTAINERS_STORAGE_CONF"] = str(self.state / "storage.conf")

    def podman(
        self, *args: str, check: bool = True, capture: bool = False, stdin: bool = False, stdout_only: bool = False
    ):
        return sh(["podman", *args], env=self.env, check=check, capture=capture, stdin=stdin, stdout_only=stdout_only)

    def running_names(self) -> list[str]:
        out = self.podman(
            "ps", "--filter", "name=^box-", "--format", "{{.Names}}", capture=True, stdout_only=True
        ).stdout
        return sorted(line.removeprefix("box-") for line in out.split() if line.startswith("box-"))


class Instance:
    def __init__(self, host: Host, name: str):
        self.host = host
        self.name = name
        self.container = f"box-{name}"
        self.dir = host.state / name

    @property
    def meta_file(self) -> Path:
        return self.dir / "meta.json"

    def running(self) -> bool:
        if self.host.podman("container", "exists", self.container, check=False).returncode != 0:
            return False
        inspect = self.host.podman(
            "inspect", "-f", "{{.State.Running}}", self.container, capture=True, stdout_only=True
        )
        return inspect.stdout.strip() == "true"

    def require_running(self) -> None:
        if not self.running():
            raise BoxError(f"{self.name}: the container is not running; start it with 'box up'")

    def take_lock(self):
        self.dir.mkdir(parents=True, exist_ok=True)
        handle = open(self.dir / "lock", "w")  # noqa: SIM115 - held until the process ends
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            raise BoxError(f"{self.name}: another up, down or build of this instance is running") from None
        return handle

    def inner(
        self, script: str, *, stdin: bool = False, capture: bool = False, check: bool = True, stdout_only: bool = False
    ):
        args = ["exec"]
        if stdin:
            args.append("-i")
        for key, value in INNER_ENV.items():
            args += ["-e", f"{key}={value}"]
        args += [self.container, "/run/current-system/sw/bin/bash", "-lc", script]
        return self.host.podman(*args, capture=capture, check=check, stdin=stdin, stdout_only=stdout_only)

    def remove_container(self) -> None:
        # SIGTERM to `podman run` is a signal that systemd inside ignores: the unit would wait its 90 s stop timeout.
        # `podman stop` sends the stop signal of systemd containers, which powers it off.
        self.host.podman("stop", "-t", "10", self.container, check=False, capture=True)
        sh(["systemctl", "--user", "stop", f"{self.container}.service"], check=False, capture=True)
        self.host.podman("rm", "-f", self.container, check=False, capture=True)

    def remove_rootfs(self) -> None:
        # Files of container users belong to subuids: only the user namespace of podman may remove them.
        self.host.podman("unshare", "rm", "-rf", str(self.dir / "rootfs"), check=False)

    def build(self, flake_dir: Path, has_home: bool, prefix: str = "") -> tuple[Path, Path | None]:
        """The out links are GC roots; `prefix` keeps a build of a running instance off the roots it runs from."""
        roots = self.dir / "roots"
        roots.mkdir(parents=True, exist_ok=True)

        def build_one(attr: str) -> Path:
            out = sh(
                [
                    "nix",
                    "build",
                    "--quiet",
                    "--option",
                    "warn-dirty",
                    "false",
                    "--out-link",
                    str(roots / f"{prefix}{attr}"),
                    "--print-out-paths",
                    f"path:{flake_dir}#{attr}",
                ],
                capture=True,
                stdout_only=True,
                what=f"build of {attr}",
            )
            return Path(out.stdout.strip().splitlines()[-1])

        # The home first: when it fails, the roots of the running system have not been replaced.
        home = build_one("home") if has_home else None
        return build_one("toplevel"), home

    def start(self, top: Path, gpu: bool) -> None:
        self.remove_container()
        sh(["systemctl", "--user", "reset-failed", f"{self.container}.service"], check=False, capture=True)
        self.remove_rootfs()
        (self.dir / "rootfs").mkdir(parents=True, exist_ok=True)
        (self.dir / "out").mkdir(parents=True, exist_ok=True)
        for old in (self.dir / "out").glob("*.ppm"):
            old.unlink()
        # keep-groups: the host group `video` gives /dev/dri/card0, which Hyprland needs even with only a headless
        # output. The daemon socket is for the nix commands of the Home Manager activation.
        devices = [arg for d in DEVICES if gpu and os.path.exists(d) for arg in ("--device", d)]
        groups = ["--group-add", "keep-groups"] if gpu else []
        driver = (
            ["-v", "/run/opengl-driver:/run/opengl-driver:ro"] if gpu and os.path.isdir("/run/opengl-driver") else []
        )
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
            *groups,
            "-v",
            "/nix/store:/nix/store:ro",
            "-v",
            "/nix/var/nix/daemon-socket:/nix/var/nix/daemon-socket",
            "-v",
            f"{self.dir}/out:/out",
            *driver,
            *devices,
            "--tmpfs",
            "/run/wrappers:rw,exec,suid,mode=755",
            str(self.dir / "rootfs"),
            f"{top}/init",
        ]
        sh(cmd, env=self.host.env, what="systemd-run of the container")

    def wait_up(self) -> str:
        deadline = time.monotonic() + BOOT_WAIT_SECONDS
        while time.monotonic() < deadline:
            if self.running():
                state = self.system_state()
                if state in ("running", "degraded"):
                    return state
            # No --collect on the unit: a failed podman run stays and its journal says why.
            if sh(["systemctl", "--user", "is-active", "--quiet", f"{self.container}.service"], check=False).returncode:
                sh(["journalctl", "--user", "-u", f"{self.container}.service", "--no-pager", "-n", "15"], check=False)
                self.remove_container()
                raise BoxError(f"{self.name}: podman run exited")
            time.sleep(2)
        self.remove_container()
        raise BoxError(f"{self.name}: systemd in the container did not come up in {BOOT_WAIT_SECONDS} s")

    def system_state(self) -> str:
        return self.inner("systemctl is-system-running", capture=True, check=False, stdout_only=True).stdout.strip()

    def activate(self, home: Path) -> None:
        # A file Hyprland wrote on its first start would block the activation: keep it as .bak.
        self.inner(f"HOME_MANAGER_BACKUP_EXT=bak HOME_MANAGER_BACKUP_OVERWRITE=1 {home}/activate")

    def down(self) -> None:
        self.remove_container()
        self.remove_rootfs()

    def save_meta(self, meta: dict) -> None:
        tmp = self.dir / f"meta.json.tmp.{os.getpid()}"
        tmp.write_text(json.dumps(meta))
        os.replace(tmp, self.meta_file)

    def load_meta(self) -> dict:
        if not self.meta_file.is_file():
            raise BoxError(f"{self.name}: no metadata; start it with 'box up'")
        return json.loads(self.meta_file.read_text())

    @staticmethod
    def with_prelude(text: str, layers: list[Layer], strict: bool = True) -> str:
        """A script after the lib.sh of every layer, so that its helpers are available."""
        libs = "".join(layer.lib.read_text() + "\n" for layer in layers if layer.lib)
        return ("set -eo pipefail\n" if strict else "") + libs + text

    def run_script(self, text: str, layers: list[Layer]) -> subprocess.CompletedProcess:
        """Runs a fixture or check script in the container and captures its output."""
        return self.inner(self.with_prelude(text, layers), capture=True, check=False)


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


def note(message: str) -> None:
    print(f"box: {message}", file=sys.stderr)
