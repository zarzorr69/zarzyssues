import importlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
overlay = importlib.import_module('zarzysseus_overlay')
bridge = importlib.import_module('zarzysseus_bridge')


class DockerToolkitTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name) / 'app'
        (self.root / 'src').mkdir(parents=True)
        (self.root / 'app.py').write_text('')
        self.source = self.root / 'src' / 'agent_loop.py'
        self.source.write_text('value = 1\n')
        self.storage = self.root / 'data' / 'local' / 'zarzysseus-docker' / 'overlay'

    def tearDown(self):
        self.temp.cleanup()

    def test_repairs_survive_recreation_and_preserve_original_baseline(self):
        before = overlay.snapshot(self.root)
        self.source.write_text('value = 2\n')
        self.assertEqual(overlay.capture(self.root, self.storage, before), ['src/agent_loop.py'])
        before = overlay.snapshot(self.root)
        self.source.write_text('value = 3\n')
        overlay.capture(self.root, self.storage, before)
        state = overlay.read_index(self.storage)['files']['src/agent_loop.py']
        self.assertEqual(overlay.read_blob(self.storage, state['base']), b'value = 1\n')
        self.source.write_text('value = 1\n')  # Original file in a recreated container.
        self.assertEqual(overlay.apply(self.root, self.storage), 1)
        self.assertEqual(self.source.read_text(), 'value = 3\n')
        self.assertEqual(overlay.apply(self.root, self.storage), 1)

    def test_upstream_drift_is_rejected_before_any_file_is_changed(self):
        second = self.root / 'src' / 'other.py'
        second.write_text('old = 1\n')
        before = overlay.snapshot(self.root)
        self.source.write_text('value = 2\n')
        second.write_text('old = 2\n')
        overlay.capture(self.root, self.storage, before)
        self.source.write_text('value = 1\n')
        second.write_text('upstream_changed = True\n')
        with self.assertRaises(ValueError):
            overlay.apply(self.root, self.storage)
        self.assertEqual(self.source.read_text(), 'value = 1\n')

    def test_corrupt_blobs_and_path_escape_are_rejected(self):
        before = overlay.snapshot(self.root)
        self.source.write_text('value = 2\n')
        overlay.capture(self.root, self.storage, before)
        state = overlay.read_index(self.storage)['files']['src/agent_loop.py']
        (self.storage / 'blobs' / state['patched']).write_text('corrupted')
        with self.assertRaises(ValueError):
            overlay.apply(self.root, self.storage)
        for relative in ('../secret.py', '/tmp/secret.py', 'data/private.py', 'src/../private.py'):
            with self.assertRaises(ValueError):
                overlay.target_path(self.root, relative)

    def test_native_rollback_removes_replay_record(self):
        before = overlay.snapshot(self.root)
        self.source.write_text('value = 2\n')
        overlay.capture(self.root, self.storage, before)
        before = overlay.snapshot(self.root)
        self.source.write_text('value = 1\n')
        overlay.capture(self.root, self.storage, before)
        self.assertEqual(overlay.read_index(self.storage)['files'], {})

    def test_native_installer_and_unverified_toolkit_cannot_run(self):
        with patch.object(bridge.subprocess, 'run') as command:
            for action in ('install', 'system-update', 'accelerator-setup', 'uninstall', 'tui'):
                with self.subTest(action=action), self.assertRaises(ValueError):
                    bridge.run_action(self.root, action, [])
            command.assert_not_called()
        with self.assertRaises(ValueError):
            bridge.adapt('unverified content')

    def test_host_menu_forwards_arguments_without_installing_native_stack(self):
        fake_bin = Path(self.temp.name) / 'bin'
        fake_bin.mkdir()
        log = Path(self.temp.name) / 'calls.txt'
        docker = fake_bin / 'docker'
        docker.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$DOCKER_TEST_LOG"\nexit 0\n')
        docker.chmod(0o755)
        kit = Path(self.temp.name) / 'kit'
        kit.mkdir()
        for filename in ('zarzysseus-docker.sh', 'run.sh', 'compose.yaml', '.env.example'):
            shutil.copy2(ROOT / filename, kit / filename)
        (kit / '.env').write_text('APP_UID=999\nAPP_GID=1000\n')
        import os
        env = dict(os.environ, PATH=str(fake_bin) + ':' + os.environ['PATH'], DOCKER_TEST_LOG=str(log))
        result = subprocess.run(['bash', str(kit / 'run.sh'), 'zarzysseus', 'skills-search', 'office $(false)'],
                                env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = log.read_text()
        self.assertIn('--user 999:1000 odysseus python /cpu-kit/zarzysseus_bridge.py run skills-search office $(false)', calls)
        self.assertNotIn('ollama pull', calls)
        self.assertNotIn('up -d', calls)


if __name__ == '__main__':
    unittest.main()
