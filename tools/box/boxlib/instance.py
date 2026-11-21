"""Host side of a box instance: what every backend (container, VM) shares."""

import fcntl
import json
import os
import shlex
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

from .layers import SYSTEM_ATTR, Layer


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

    def running_names(self) -> list[str]:
        """The instances of every backend: each runs as the transient user unit box-<name>."""
        out = sh(
            [
                "systemctl",
                "--user",
                "list-units",
                "box-*.service",
                "--state=active,activating",
                "--plain",
                "--no-legend",
            ],
            capture=True,
            stdout_only=True,
            check=False,
        ).stdout
        return sorted(
            line.split()[0].removeprefix("box-").removesuffix(".service") for line in out.splitlines() if line
        )


class Instance:
    """One system (and home) running in some backend. The subclasses are ContainerInstance and VmInstance."""

    backend = ""
    boot_wait = 120  # seconds until the system runs

    def __init__(self, host: Host, name: str, user: str | None = None):
        self.host = host
        self.name = name
        self.system_attr = SYSTEM_ATTR[self.backend]
        self.user = user  # the session user: the user of the home, else the one the system layer names
        self.unit = f"box-{name}"
        self.dir = host.state / name

    @property
    def meta_file(self) -> Path:
        return self.dir / "meta.json"

    def take_lock(self):
        self.dir.mkdir(parents=True, exist_ok=True)
        handle = open(self.dir / "lock", "w")  # noqa: SIM115 - held until the process ends
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            raise BoxError(f"{self.name}: another up, down or build of this instance is running") from None
        return handle

    def require_running(self) -> None:
        if not self.running():
            raise BoxError(f"{self.name}: not running; start it with 'box up'")

    def stop_unit(self) -> None:
        sh(["systemctl", "--user", "stop", f"{self.unit}.service"], check=False, capture=True)

    def reset_unit(self) -> None:
        sh(["systemctl", "--user", "reset-failed", f"{self.unit}.service"], check=False, capture=True)

    def unit_active(self) -> bool:
        return sh(["systemctl", "--user", "is-active", "--quiet", f"{self.unit}.service"], check=False).returncode == 0

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
        return build_one(self.system_attr), home

    def configure(self, flake_dir: Path, has_home: bool) -> None:
        """The session user is the user of the home; a system without a home leaves it to the layer."""
        if has_home:
            out = sh(
                ["nix", "eval", "--raw", f"path:{flake_dir}#lib.username"],
                capture=True,
                stdout_only=True,
                what="reading the user of the home",
            )
            self.user = out.stdout.strip()

    def check_host(self, gpu: bool) -> None:
        """Fails with a message when the host cannot run this backend (with a GPU when `gpu`)."""

    def save_meta(self, meta: dict) -> None:
        tmp = self.dir / f"meta.json.tmp.{os.getpid()}"
        tmp.write_text(json.dumps({"backend": self.backend, **meta}))
        os.replace(tmp, self.meta_file)

    def load_meta(self) -> dict:
        if not self.meta_file.is_file():
            raise BoxError(f"{self.name}: no metadata; start it with 'box up'")
        return json.loads(self.meta_file.read_text())

    def prelude_vars(self) -> str:
        """Shell lines that come before the lib.sh of the layers."""
        return f"BOX_USER={shlex.quote(self.user)}\n" if self.user else ""

    def with_prelude(self, text: str, layers: list[Layer], strict: bool = True) -> str:
        """A script after the lib.sh of every layer, so that its helpers are available."""
        libs = "".join(layer.lib.read_text() + "\n" for layer in layers if layer.lib)
        return ("set -eo pipefail\n" if strict else "") + self.prelude_vars() + libs + text

    def run_script(self, text: str, layers: list[Layer]) -> subprocess.CompletedProcess:
        """Runs a fixture or check script in the system and captures its output."""
        return self.inner(self.with_prelude(text, layers), capture=True, check=False)

    # The backend implements these.
    def running(self) -> bool:
        raise NotImplementedError

    def start(self, top: Path, gpu: bool) -> None:
        raise NotImplementedError

    def inner(
        self, script: str, *, stdin: bool = False, capture: bool = False, check: bool = True, stdout_only: bool = False
    ) -> subprocess.CompletedProcess:
        raise NotImplementedError

    def down(self) -> None:
        raise NotImplementedError

    def prepare_out(self) -> None:
        """The directory the system shares with the host for frames, empty at every start."""
        (self.dir / "out").mkdir(parents=True, exist_ok=True)
        for old in (self.dir / "out").glob("*.ppm"):
            old.unlink()

    def ready(self) -> bool:
        """True when commands can run in the system."""
        raise NotImplementedError

    def show_failure(self) -> None:
        sh(["journalctl", "--user", "-u", f"{self.unit}.service", "--no-pager", "-n", "15"], check=False)

    def wait_up(self) -> str:
        """Waits until systemd of the system runs (or is degraded) and returns its state; a start that fails is torn
        down."""
        deadline = time.monotonic() + self.boot_wait
        while time.monotonic() < deadline:
            # No --collect on the unit: a failed run stays and its journal says why.
            if not self.unit_active():
                self.show_failure()
                self.down()
                raise BoxError(f"{self.name}: the {self.backend} exited")
            if self.ready():
                state = self.system_state()
                if state in ("running", "degraded"):
                    return state
            time.sleep(2)
        self.show_failure()
        self.down()
        raise BoxError(f"{self.name}: the {self.backend} did not come up in {self.boot_wait} s")

    def activate(self, home: Path, layers: list[Layer]) -> None:
        """Runs the activation of the home as its user, once the user manager and its bus are up. A file Hyprland
        wrote on its first start would block it: it is kept as .bak."""
        if not self.user:
            raise BoxError(f"{self.name}: no session user to activate the home for")
        script = (
            f"box_session_up\nbox_user env HOME_MANAGER_BACKUP_EXT=bak HOME_MANAGER_BACKUP_OVERWRITE=1 {home}/activate"
        )
        self.inner(self.with_prelude(script, layers))

    def system_state(self) -> str:
        return self.inner("systemctl is-system-running", capture=True, check=False, stdout_only=True).stdout.strip()


def note(message: str) -> None:
    print(f"box: {message}", file=sys.stderr)
