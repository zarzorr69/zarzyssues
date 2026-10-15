"""Offline installer/network tests for V11.4. No real Docker operations."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
CONTROLLER = ROOT/'docker/zarzysseus-docker.sh'
WIN = ROOT/'docker/zarzysseus-docker.ps1'

FAKE_DOCKER = '''#!/usr/bin/env bash
set -eu
if [[ "${1:-}" == info ]]; then echo "Docker Server: mock"; exit 0; fi
if [[ "${1:-}" == compose ]]; then
  shift
  case " $* " in
    *" version "*) echo 'Docker Compose version v2-mock'; exit 0 ;;
    *" ps "*) exit 0 ;;
    *" /cpu-kit/admin_preseed.py status "*) echo EXISTING_AUTH_PRESERVED; exit 0 ;;
    *" exec "*)
        if [[ " $* " == *" /api/auth/status"* || " $* " == *" api/auth/status"* ]]; then
            echo '{"configured":true,"authenticated":false}'
        fi
        exit 0 ;;
  esac
  exit 0
fi
exit 0
'''

class NetworkInstallTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.d = Path(self.tmp.name)
        self.kit = self.d/'kit'; self.kit.mkdir()
        for name in ['compose.yaml','run.sh','zarzysseus-docker.sh','.env.example','admin_preseed.py']:
            shutil.copy2(ROOT/'docker'/name,self.kit/name)
        (self.kit/'models').mkdir()
        for name in ['Modelfile.quality','Modelfile.agent','Modelfile.moe']:
            shutil.copy2(ROOT/'docker/models'/name,self.kit/'models'/name)
        (self.kit/'.env').write_text('APP_BIND=127.0.0.1\nAPP_PORT=7012\nAPP_ORIGIN=http://localhost:7012\nAUTH_ENABLED=true\nKEEP_ME=original\n')
        self.bin=self.d/'bin';self.bin.mkdir()
        (self.bin/'docker').write_text(FAKE_DOCKER)
        (self.bin/'docker').chmod(0o755)
        self.env = dict(os.environ,
            PATH=str(self.bin)+os.pathsep+os.environ['PATH'],
            ZARZYSSEUS_DOCKER_SUDO='0',
            ZARZYSSEUS_KIT_DIR=str(self.kit),
            ZARZYSSEUS_PROFILE='cpu')

    def invoke(self, *args, inp='', approvals=None):
        env=dict(self.env)
        if approvals:env['ZARZYSSEUS_CONFIRM']=approvals
        return subprocess.run(['bash',str(CONTROLLER),*args],cwd=self.kit,env=env,
                              input=inp,text=True,capture_output=True,timeout=20)

    def test_network_status_is_read_only(self):
        before=(self.kit/'.env').read_bytes()
        r=self.invoke('network-status')
        self.assertEqual(r.returncode,0,r.stderr)
        self.assertIn('127.0.0.1',r.stdout)
        self.assertEqual(before,(self.kit/'.env').read_bytes())

    def test_network_update_atomic_and_preserves_unrelated(self):
        r=self.invoke('network-configure',inp='2\n192.168.1.156\n7012\n\n',approvals='NETWORK')
        self.assertEqual(r.returncode,0,r.stderr+r.stdout)
        data=(self.kit/'.env').read_text()
        self.assertIn('APP_BIND=192.168.1.156\n',data)
        self.assertIn('APP_ORIGIN=http://192.168.1.156:7012\n',data)
        self.assertIn('KEEP_ME=original\n',data)
        self.assertIn('AUTH_ENABLED=true\n',data)
        backups=list(self.kit.glob('.env.zarzysseus-backup.*'))
        self.assertEqual(len(backups),1)
        self.assertIn('APP_BIND=127.0.0.1',backups[0].read_text())
        self.assertEqual((self.kit/'.env').stat().st_mode & 0o777,0o600)

    def test_network_rejects_invalid_without_mutation(self):
        before=(self.kit/'.env').read_bytes()
        r=self.invoke('network-configure',inp='2\n256.0.0.1\n7012\n',approvals='NETWORK')
        self.assertNotEqual(r.returncode,0)
        self.assertEqual(before,(self.kit/'.env').read_bytes())
        self.assertEqual(list(self.kit.glob('.env.zarzysseus-backup.*')),[])

    def test_existing_admin_is_preserved(self):
        r=self.invoke('auth-setup')
        # A fake API might be absent; in all cases there must not be a local auth reset.
        self.assertEqual(r.returncode,0,r.stderr+r.stdout)
        self.assertIn('already exists',r.stdout)

    def test_linux_install_skip_model_no_crash(self):
        # Six-step installer uses mocked Compose. An actual image is never pulled.
        for name in ['launch_odysseus.py','zarzysseus_bridge.py','container-entrypoint.sh','zarzysseus_overlay.py']:
            shutil.copy2(ROOT/'docker'/name,self.kit/name)
        (self.kit/'config/searxng').mkdir(parents=True)
        (self.kit/'workspace').mkdir()
        r=self.invoke('install',inp='n\nn\n',approvals='INSTALL')
        self.assertEqual(r.returncode,0,r.stderr+r.stdout)
        for step in range(1,7):self.assertIn(f'STEP {step}/6:',r.stdout)
        self.assertIn('user accounts are preserved',r.stdout)

    def test_windows_source_exposes_equal_categories(self):
        w=WIN.read_text(encoding='utf-8-sig')
        for name in ['Install-Stack','Show-InstallStep','Get-AdminProvisionStatus','Setup-Admin','network-configure','network-apply','network-status']:
            self.assertIn(name,w)
        self.assertIn('Read-Host -AsSecureString',w)
        self.assertNotIn('ODYSSEUS_ADMIN_PASSWORD=',w)

if __name__ == '__main__': unittest.main()
