"""V11.5: read-only model visibility and opt-in missing-admin-helper recovery."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / 'docker/zarzysseus-docker.sh'

FAKE_DOCKER = '''#!/usr/bin/env bash
set -eu
if [[ "${1:-}" == info ]]; then exit 0; fi
if [[ "${1:-}" == compose ]]; then
  case " $* " in
    *" compose version "*) exit 0 ;;
    *" ollama list "*) printf 'NAME ID SIZE\\nqwen3.5-zarzysseus-cpu:4b mock 2.5GB\\n'; exit 0 ;;
    *" /cpu-kit/admin_preseed.py status "*) printf 'EXISTING_AUTH_PRESERVED\\n'; exit 0 ;;
    *" -c "*) printf 'OLLAMA_API_OK models=1\\n  qwen3.5-zarzysseus-cpu:4b\\n'; exit 0 ;;
  esac
  exit 0
fi
exit 0
'''

FAKE_LAUNCHER = '''#!/usr/bin/env bash
set -eu
case " $* " in
  *"docker-kit-sync apply"*)
      test "${ZARZYSSEUS_SYNC_CONFIRM:-}" == 'SYNC' || exit 6
      cp "${RELEASE_DOCKER}/admin_preseed.py" "${ZARZYSSEUS_KIT_DIR}/admin_preseed.py"
      cat "${RELEASE_DOCKER}/compose.yaml" > "${ZARZYSSEUS_KIT_DIR}/compose.yaml"
      echo 'SIMULATED_SYNC_APPLIED';;
  *"docker-kit-sync"*) echo 'SIMULATED_SYNC_PREVIEW';;
  *) exit 4;;
esac
'''

class ModelAuthTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
        self.kit=self.root/'kit';self.kit.mkdir()
        for item in ('compose.yaml','run.sh','admin_preseed.py'):
            shutil.copy2(ROOT/'docker'/item,self.kit/item)
        (self.kit/'.env').write_text('APP_BIND=127.0.0.1\nAPP_PORT=7012\nAPP_ORIGIN=http://localhost:7012\nCUSTOM=keep\n')
        bin_dir=self.root/'bin';bin_dir.mkdir()
        docker=bin_dir/'docker';docker.write_text(FAKE_DOCKER);docker.chmod(0o755)
        launcher=bin_dir/'launcher';launcher.write_text(FAKE_LAUNCHER);launcher.chmod(0o755)
        self.env=dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}",
                      ZARZYSSEUS_DOCKER_SUDO='0',ZARZYSSEUS_KIT_DIR=str(self.kit),
                      ZARZYSSEUS_PROFILE='cpu',ZARZYSSEUS_MODE_SWITCH_CMD=str(launcher),
                      RELEASE_DOCKER=str(ROOT/'docker'))
    def invoke(self, action, **env):
        return subprocess.run(['bash',str(HELPER),action],capture_output=True,text=True,
                              input='',env={**self.env,**env},timeout=12)
    def test_doctor_does_not_modify_env_or_models(self):
        prev=(self.kit/'.env').read_bytes()
        proc=self.invoke('model-doctor')
        self.assertEqual(proc.returncode,0,proc.stderr+proc.stdout)
        self.assertIn('qwen3.5-zarzysseus-cpu:4b',proc.stdout)
        self.assertIn('OLLAMA_API_OK models=1',proc.stdout)
        self.assertEqual(prev,(self.kit/'.env').read_bytes())
    def test_existing_admin_preserved(self):
        proc=self.invoke('auth-setup')
        self.assertEqual(proc.returncode,0,proc.stdout+proc.stderr)
        self.assertIn('already exists',proc.stdout)
    def test_missing_helper_without_tty_fails_closed(self):
        (self.kit/'admin_preseed.py').unlink()
        prev=(self.kit/'.env').read_bytes()
        proc=self.invoke('auth-setup')
        self.assertNotEqual(proc.returncode,0)
        self.assertIn('NEEDS SYNC',proc.stderr)
        self.assertIn('Approval required: SYNC',proc.stderr)
        self.assertEqual(prev,(self.kit/'.env').read_bytes())
        self.assertFalse((self.kit/'admin_preseed.py').exists())
    def test_explicit_sync_can_restore_helper(self):
        (self.kit/'admin_preseed.py').unlink()
        proc=self.invoke('auth-setup',ZARZYSSEUS_CONFIRM='SYNC')
        self.assertEqual(proc.returncode,0,proc.stdout+proc.stderr)
        self.assertIn('SIMULATED_SYNC_APPLIED',proc.stderr)
        self.assertIn('already exists',proc.stdout)
        self.assertIn('CUSTOM=keep',(self.kit/'.env').read_text())
    def test_windows_exposes_model_doctor(self):
        source=(ROOT/'docker/zarzysseus-docker.ps1').read_text(encoding='utf-8-sig')
        self.assertIn('function Show-ModelDoctor',source)
        self.assertIn('OLLAMA_API_OK',source)
        self.assertIn("'model-doctor' { Show-ModelDoctor",source)
    def test_o_dot_hostname_refused_before_mutation(self):
        prev=(self.kit/'.env').read_bytes()
        proc=subprocess.run(['bash',str(HELPER),'network-configure'],capture_output=True,text=True,
                            input='3\n7012\nhttp://o.o.o.o:7012\n', env=self.env,timeout=12)
        self.assertNotEqual(proc.returncode,0)
        self.assertIn('letter-o.o.o.o',proc.stderr)
        self.assertEqual((self.kit/'.env').read_bytes(),prev)

if __name__ == '__main__': unittest.main()
