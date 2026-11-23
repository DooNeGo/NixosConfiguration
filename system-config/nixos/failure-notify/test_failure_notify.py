import fcntl
import os
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path


class FailureNotifyTests(unittest.TestCase):
    def test_simultaneous_reports_notify_once(self):
        def waiting_for_lock(process):
            try:
                children = Path(f"/proc/{process.pid}/task/{process.pid}/children").read_text().split()
                return any(Path(f"/proc/{child}/comm").read_text().strip() == "flock" for child in children)
            except FileNotFoundError:
                return False

        script = Path(__file__).with_name("failure-notify.sh")
        with tempfile.TemporaryDirectory() as tmp:
            state = Path(tmp)
            (state / "same").write_text("1000\n0\n0\nprevious\n")
            env = {
                "PATH": os.environ["PATH"],
                "FAILURE_NOTIFY_STATE_DIR": tmp,
                "FAILURE_NOTIFY_RENOTIFY_SEC": "86400",
                "FAILURE_NOTIFY_SINKS": shutil.which("printenv"),
            }
            with (state / ".lock").open("w") as lock:
                fcntl.flock(lock, fcntl.LOCK_EX)
                processes = [
                    subprocess.Popen(
                        ["bash", str(script), "report", "same", f"message {i}"],
                        env=env,
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        text=True,
                    )
                    for i in range(2)
                ]
                deadline = time.monotonic() + 10
                while time.monotonic() < deadline:
                    if all(waiting_for_lock(process) for process in processes):
                        break
                    time.sleep(0.01)
                else:
                    self.fail("reports did not wait for the lock")
                fcntl.flock(lock, fcntl.LOCK_UN)
            results = [process.communicate(timeout=10) for process in processes]
            self.assertEqual([process.returncode for process in processes], [0, 0], results)
            self.assertEqual(sum("FAILED_UNIT=same" in stdout for stdout, _ in results), 1)
            self.assertEqual((state / "same").read_text().splitlines()[0], "1000")


if __name__ == "__main__":
    unittest.main()
