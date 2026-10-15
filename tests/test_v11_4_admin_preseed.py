"""A real Python execution test of the guarded first-admin helper (fake auth data)."""
import contextlib
import io
import os
from pathlib import Path
import runpy
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

HELPER = Path(__file__).resolve().parents[1] / 'docker/admin_preseed.py'


class AdminPreseedTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.auth_file = Path(tmp.name) / 'auth.json'
        self.calls = []

    def execute(self, args, data=''):
        const = types.ModuleType('src.constants')
        const.AUTH_FILE = str(self.auth_file)
        const.PASSWORD_MIN_LENGTH = 12
        coreauth = types.ModuleType('core.auth')
        coreauth.RESERVED_USERNAMES = {'root', 'system'}
        outer = self

        class AuthManager:
            @property
            def is_configured(self):
                return outer.auth_file.is_file()

            def setup(self, username, password):
                outer.calls.append((username, password))
                outer.auth_file.write_text('MOCK HASH ONLY')
                return True

        coreauth.AuthManager = AuthManager
        mocked = {'src':types.ModuleType('src'), 'src.constants':const,
                  'core':types.ModuleType('core'), 'core.auth':coreauth}
        stdout = io.StringIO()
        with patch.dict(sys.modules, mocked), patch.object(sys, 'argv', [str(HELPER)] + args), \
             patch.object(sys, 'stdin', io.StringIO(data)), patch('os.chdir'), \
             patch('os.geteuid', return_value=1000), contextlib.redirect_stdout(stdout):
            try:
                runpy.run_path(str(HELPER), run_name='__main__')
            except SystemExit as e:
                return e.code, stdout.getvalue()
        return 0, stdout.getvalue()

    def test_empty_first_run_is_available(self):
        code, output = self.execute(['status'])
        self.assertEqual(code, 0)
        self.assertIn('FIRST_RUN_AVAILABLE', output)

    def test_admin_created_without_echoing_password(self):
        code, output = self.execute(['999','1000'], 'MyAdmin\nTestSecret12?x\n')
        self.assertEqual(code, 0)
        self.assertIn('ADMIN_CREATED', output)
        self.assertNotIn('TestSecret12?x', output)
        self.assertEqual(self.calls, [('myadmin','TestSecret12?x')])

    def test_existing_account_never_overwritten(self):
        self.auth_file.write_text('{"users":{"somebody":{}}}')
        code, output = self.execute(['999','1000'], 'newadmin\nTestSecret12?x\n')
        self.assertEqual(code, 0)
        self.assertIn('EXISTING_AUTH_PRESERVED', output)
        self.assertEqual(self.calls, [])
        self.assertIn('somebody', self.auth_file.read_text())

    def test_invalid_username_and_password_do_not_write(self):
        for data in ['root\nTestSecret12?x\n', 'test\nshort\n', 'bad/user\nTestSecret12?x\n']:
            code, _ = self.execute(['999','1000'], data)
            self.assertNotEqual(code, 0)
            self.assertFalse(self.auth_file.exists())


if __name__ == '__main__':
    unittest.main()
