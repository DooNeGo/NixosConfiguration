import subprocess
import tempfile
import unittest
from pathlib import Path


class BenchmarkSafetyTest(unittest.TestCase):
    def test_dry_benchmark_preserves_existing_files(self):
        script = Path(__file__).with_name("btrfs-compress-force-test.sh")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ("dest", "ram", "source"):
                (root / name).mkdir()
                (root / name / "keep").write_bytes(b"x" * 1_000_000)
            result = subprocess.run(
                [
                    "bash",
                    str(script),
                    "--dry",
                    "--dest",
                    str(root / "dest"),
                    "--ram",
                    str(root / "ram"),
                    "--dataset",
                    f"test|{root / 'source'}|1",
                    "--csv",
                    str(root / "out.csv"),
                    "--md",
                    str(root / "out.md"),
                    "--writers",
                    "1",
                    "--levels=-1",
                    "--modes",
                    "compress",
                ],
                capture_output=True,
                text=True,
                check=False,
                timeout=60,
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            for name in ("dest", "ram", "source"):
                self.assertEqual((root / name / "keep").stat().st_size, 1_000_000)
            self.assertTrue((root / "out.md").is_file())

    def test_existing_files_survive_failure_and_overlaps_are_refused(self):
        script = Path(__file__).with_name("btrfs-compress-force-test.sh")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ("dest", "ram", "source"):
                (root / name).mkdir()
                (root / name / "keep").write_text(name)
            common = ["bash", str(script), "--dry", "--csv", str(root / "out.csv"), "--md", str(root / "out.md")]
            for dest, ram, source in (
                (root / "dest", root / "ram", root / "missing"),
                (root / "source", root / "ram", root / "source"),
            ):
                result = subprocess.run(
                    [*common, "--dest", str(dest), "--ram", str(ram), "--dataset", f"test|{source}|1"],
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertNotEqual(result.returncode, 0)
                for name in ("dest", "ram", "source"):
                    self.assertEqual((root / name / "keep").read_text(), name)


if __name__ == "__main__":
    unittest.main()
