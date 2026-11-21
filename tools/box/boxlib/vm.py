"""The VM backend: QEMU runs the system (NixOS qemu-vm.nix) with the host store shared read-only over virtiofs.

The guest has no network. Commands go over ssh on AF_VSOCK as the guest root with a key made per start and handed
to the guest as a systemd credential. A GPU layer gets a virtio GPU with OpenGL (virglrenderer) that renders on
the host render node: it is not the NVIDIA of the host.
"""

import base64
import os
import shlex
import shutil
import subprocess
import sys
import zlib
from pathlib import Path

from .instance import BoxError, Instance, sh

SSH_PORT = 22
DEVICES = ("/dev/kvm", "/dev/vhost-vsock")
RENDER_NODES = sorted(Path("/dev/dri").glob("renderD*")) if Path("/dev/dri").is_dir() else []


def guest_cid(name: str) -> int:
    """The vsock address of a guest: from the instance name, so a command finds it without any state (3 is the first
    free one; a clash with another running guest makes QEMU fail at start)."""
    return 100 + zlib.crc32(name.encode()) % 1_000_000


def qemu_options(cid: int, console: Path, credential: str, render_node: Path | None) -> list[str]:
    options = [
        "-serial",
        f"file:{console}",
        "-monitor",
        "none",
        "-device",
        f"vhost-vsock-pci,guest-cid={cid}",
        # systemd turns this into the credential that box-authorized-keys installs for root
        "-smbios",
        f"type=11,value=io.systemd.credential.binary:ssh.authorized_keys.root={credential}",
    ]
    if render_node:
        return options + [
            "-device",
            "virtio-vga-gl",
            "-display",
            f"egl-headless,gl=on,rendernode={render_node}",
        ]
    return options + ["-display", "none"]


class VmInstance(Instance):
    backend = "vm"
    boot_wait = 240

    def __init__(self, host, name: str, user: str | None = None):
        super().__init__(host, name, user)
        self.cid = guest_cid(name)

    @property
    def run_dir(self) -> Path:
        return self.dir / "run"

    @property
    def key(self) -> Path:
        return self.dir / "ssh" / "id"

    @property
    def console(self) -> Path:
        return self.dir / "console.log"

    def running(self) -> bool:
        return self.unit_active()

    def check_host(self, gpu: bool) -> None:
        for device in DEVICES:
            if not Path(device).exists():
                raise BoxError(f"{device} is missing: the VM backend needs KVM and vhost-vsock")
            if not _writable(device):
                raise BoxError(f"{device} is not writable for this user")
        if gpu and not RENDER_NODES:
            raise BoxError("a layer asks for a GPU and the host has no /dev/dri/renderD* for the virtual one")
        if gpu and not _writable(str(RENDER_NODES[0])):
            raise BoxError(f"{RENDER_NODES[0]} is not writable for this user")
        for tool in ("ssh", "ssh-keygen"):
            if not shutil.which(tool):
                raise BoxError(f"{tool} is not on PATH")

    def start(self, top: Path, gpu: bool) -> None:
        self.down()
        self.reset_unit()
        for sub in ("run", "ssh"):
            (self.dir / sub).mkdir(parents=True, exist_ok=True)
        self.prepare_out()
        self.console.unlink(missing_ok=True)
        for old in self.key.parent.glob("id*"):
            old.unlink()
        sh(
            ["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-C", f"box-{self.name}", "-f", str(self.key)],
            what="ssh-keygen",
        )
        credential = base64.b64encode(self.key.with_suffix(".pub").read_bytes()).decode()
        options = qemu_options(self.cid, self.console, credential, RENDER_NODES[0] if gpu else None)
        cmd = [
            "systemd-run",
            "--user",
            "--quiet",
            f"--unit={self.unit}",
            f"--setenv=TMPDIR={self.run_dir}",
            f"--setenv=QEMU_OPTS={' '.join(options)}",
            "--setenv=QEMU_KERNEL_PARAMS=console=ttyS0",
            f"{top}/bin/run-nixos-vm",
        ]
        sh(cmd, env=self.host.env, what="systemd-run of the VM")

    def ssh_command(self) -> list[str]:
        proxy = shlex.join(
            [sys.executable, "-I", str(Path(__file__).with_name("vsock_proxy.py")), str(self.cid), str(SSH_PORT)]
        )
        return [
            "ssh",
            "-F",
            "/dev/null",
            "-i",
            str(self.key),
            "-o",
            "IdentitiesOnly=yes",
            "-o",
            "BatchMode=yes",
            "-o",
            "StrictHostKeyChecking=no",
            "-o",
            "UserKnownHostsFile=/dev/null",
            "-o",
            "LogLevel=ERROR",
            "-o",
            "ConnectTimeout=10",
            "-o",
            "ServerAliveInterval=5",
            "-o",
            f"ProxyCommand={proxy}",
            "root@box",
        ]

    def inner(
        self, script: str, *, stdin: bool = False, capture: bool = False, check: bool = True, stdout_only: bool = False
    ) -> subprocess.CompletedProcess:
        remote = shlex.join(["bash", "-lc", script])
        return sh(
            [*self.ssh_command(), "-T", "--", remote],
            capture=capture,
            check=check,
            stdin=stdin,
            stdout_only=stdout_only,
            what="a command in the VM",
        )

    def ready(self) -> bool:
        return self.inner("true", capture=True, check=False).returncode == 0

    def show_failure(self) -> None:
        super().show_failure()
        if self.console.is_file():
            print("\n".join(self.console.read_text(errors="replace").splitlines()[-25:]), file=sys.stderr)

    def down(self) -> None:
        self.stop_unit()
        shutil.rmtree(self.run_dir, ignore_errors=True)


def _writable(path: str) -> bool:
    return os.access(path, os.R_OK | os.W_OK)
