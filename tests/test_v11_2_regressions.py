"""V11.2 Linux-only regressions. No real Docker daemon, downloads, or models."""
import fcntl
import os
from pathlib import Path
import pty
import select
import shutil
import subprocess
import tempfile
import termios
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "docker" / "zarzysseus-docker.sh"


def _tty_child(argv, env):
    master, slave = pty.openpty()
    def attach():
        os.setsid()
        fcntl.ioctl(0, termios.TIOCSCTTY, 0)
    process = subprocess.Popen(argv, stdin=slave, stdout=slave, stderr=slave, env=env, preexec_fn=attach)
    os.close(slave)
    return master, process


def _read_until(master, phrase, seconds=5):
    deadline = time.monotonic() + seconds
    out = b""
    while time.monotonic() < deadline:
        if not select.select([master], [], [], 0.1)[0]:
            continue
        try:
            out += os.read(master, 8192)
        except OSError:
            break
        if phrase in out:
            return out
    raise AssertionError(f"Missing {phrase!r} in output: {out[-2000:]!r}")


class DockerMenuRegression(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        root = Path(self.temp.name)
        self.kit = root / "kit"
        self.kit.mkdir()
        bin_dir = root / "bin"
        bin_dir.mkdir()
        for name in ("compose.yaml", "run.sh", "zarzysseus-docker.sh", ".env.example"):
            shutil.copyfile(ROOT / "docker" / name, self.kit / name)
        (self.kit / ".env").write_text("APP_UID=999\nAPP_GID=1000\n")
        (self.kit / "run.sh").write_text('#!/bin/bash\nprintf "SIMULATED_SETUP:%s\\n" "$*"\n')
        mock = bin_dir / "docker"
        mock.write_text('#!/bin/bash\nprintf "SIMULATED_DOCKER:%s\\n" "$*"\n')
        mock.chmod(0o755)
        self.env = {
            **os.environ,
            "PATH": f'{bin_dir}:{os.environ.get("PATH", "")}',
            "ZARZYSSEUS_KIT_DIR": str(self.kit),
            "ZARZYSSEUS_DOCKER_SUDO": "0",
            "ZARZYSSEUS_PROFILE": "cpu",
            "TERM": "xterm-256color",
        }

    def tearDown(self):
        self.temp.cleanup()

    def test_install_approval_with_one_argument(self):
        master, process = _tty_child(["bash", str(HELPER), "install"], self.env)
        try:
            out = _read_until(master, b"Type INSTALL")
            os.write(master, b"INSTALL\n")
            self.assertEqual(process.wait(timeout=5), 0)
            out += _read_until(master, b"Container installed.", seconds=2)
            self.assertIn(b"SIMULATED_SETUP:setup quality", out)
            self.assertNotIn(b"unbound variable", out)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)

    def test_arrow_key_menu_and_back_navigation(self):
        master, process = _tty_child(["bash", str(HELPER), "tui"], self.env)
        try:
            output = _read_until(master, b"DOCKER MODE")
            self.assertIn(b"\x1b[?1049h", output)
            os.write(master, b"\x1b[B\r")
            _read_until(master, b"SERVICES")
            os.write(master, b"q")
            time.sleep(0.15)
            os.write(master, b"q")
            self.assertEqual(process.wait(timeout=5), 0)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)

    def test_numbered_non_tty_fallback(self):
        result = subprocess.run(
            ["bash", str(HELPER), "tui"], input="0\n", text=True,
            capture_output=True, timeout=5, env={**self.env, "TERM": "dumb"}
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(" 1 INSTALL / UPDATE", result.stdout)

    def test_native_cpu_cannot_launch_gpu_doctor(self):
        config = Path(self.temp.name) / "mode"
        config.mkdir()
        (config / "hardware-native").write_text("cpu\n")
        result = subprocess.run(
            ["bash", str(ROOT / "zarzysseus.sh"), "native-gpu-doctor"],
            text=True, capture_output=True, timeout=5,
            env={**self.env, "ZARZYSSEUS_MODE_HOME": str(config)},
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("Native CPU-only profile", result.stderr)


if __name__ == "__main__":
    unittest.main()
