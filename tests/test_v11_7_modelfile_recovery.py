"""No-Docker regression checks for Modelfile mount validation and visible account navigation."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

MOCK = r'''#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$MOCK_LOG"
[[ "$1" == compose ]] || exit 6
shift
while [[ "$1" == --env-file || "$1" == -f ]]; do shift 2; done
case "$1" in
  version) echo "Docker Compose version v2-mock"; exit 0 ;;
  up)
    [[ "$*" == *--force-recreate* ]] && touch "$MOCK_RECREATED"
    exit 0 ;;
  exec)
    shift; [[ "$1" == -T ]] && shift
    [[ "$1" == cpu-ollama ]] || exit 6
    shift
    if [[ "$1" == cat ]]; then
      if [[ "$MOCK_MOUNT_MODE" == mounted || -f "$MOCK_RECREATED" ]]; then cat "$MOCK_HOSTFILE"; exit 0; fi
      echo 'cat: /profiles: No such file' >&2; exit 1
    fi
    if [[ "$1" == ollama ]]; then
      case "$2" in
        list) echo 'NAME SIZE'; exit 0;;
        show) exit 0;;
        create) exit 0;;
        pull) exit 0;;
      esac
    fi ;;
  run) exit 0 ;;
esac
exit 7
'''

class ModelMountTests(unittest.TestCase):
    def setUp(self):
        self.t = tempfile.TemporaryDirectory()
        self.addCleanup(self.t.cleanup)
        self.d = Path(self.t.name)
        self.kit = self.d / 'kit'
        self.kit.mkdir()
        shutil.copy2(ROOT/'docker/run.sh', self.kit/'run.sh')
        (self.kit/'.env').write_text('APP_BIND=127.0.0.1\n')
        (self.kit/'models').mkdir()
        self.hostfile=self.kit/'models/Modelfile.quality'
        shutil.copy2(ROOT/'docker/models/Modelfile.quality',self.hostfile)
        self.fakebin = self.d/'bin'; self.fakebin.mkdir()
        (self.fakebin/'docker').write_text(MOCK)
        (self.fakebin/'docker').chmod(0o755)
        self.log=self.d/'docker.log';self.remounted=self.d/'recreated'
        self.env=dict(os.environ,PATH=str(self.fakebin)+os.pathsep+os.environ['PATH'],
             MOCK_LOG=str(self.log), MOCK_RECREATED=str(self.remounted),
             MOCK_HOSTFILE=str(self.hostfile), MOCK_MOUNT_MODE='mounted')

    def run_kit(self):
        return subprocess.run(['bash',str(self.kit/'run.sh'),'setup','quality'],cwd=self.kit,
                              env=self.env,text=True,capture_output=True,timeout=20)

    def logged(self): return self.log.read_text() if self.log.exists() else ''

    def test_existing_base_not_downloaded_when_mount_correct(self):
        p=self.run_kit()
        self.assertEqual(p.returncode,0,p.stdout+p.stderr)
        self.assertIn('already installed; skipping repeat download',p.stdout)
        self.assertIn('ollama create qwen3.5-zarzysseus-cpu:4b',self.logged())
        self.assertNotIn('ollama pull ',self.logged())
        self.assertNotIn('--force-recreate',self.logged())

    def test_missing_host_file_fails_before_pull_or_create(self):
        self.hostfile.unlink()
        p=self.run_kit()
        self.assertNotEqual(p.returncode,0)
        self.assertIn('Missing/empty or unsafe host profile',p.stderr)
        self.assertNotIn('ollama pull ',self.logged())
        self.assertNotIn('ollama create ',self.logged())

    def test_missing_mount_fails_closed_without_approval(self):
        self.env['MOCK_MOUNT_MODE']='missing'
        p=self.run_kit()
        self.assertNotEqual(p.returncode,0)
        self.assertIn('MOUNT MISMATCH',p.stderr)
        self.assertFalse(self.remounted.exists())
        self.assertNotIn('ollama pull ',self.logged())

    def test_missing_mount_can_recreate_with_explicit_approval(self):
        self.env['MOCK_MOUNT_MODE']='missing'
        self.env['ZARZYSSEUS_CONFIRM']='REMOUNT'
        p=self.run_kit()
        self.assertEqual(p.returncode,0,p.stdout+p.stderr)
        self.assertIn('--force-recreate cpu-ollama',self.logged())
        self.assertTrue(self.remounted.exists())
        self.assertIn('ollama create qwen3.5-zarzysseus-cpu:4b',self.logged())
        self.assertNotIn('ollama pull ',self.logged())

    def test_account_menu_and_password_information(self):
        ctl=(ROOT/'docker/zarzysseus-docker.sh').read_text()
        self.assertIn("14) submenu 'ACCOUNT / LOGIN'",ctl)
        self.assertIn("'First-run admin account setup|auth-setup'",ctl)
        self.assertIn('Existing account: log in to Odysseus',ctl)
        win=(ROOT/'docker/zarzysseus-docker.ps1').read_text(encoding='utf-8-sig')
        self.assertIn("14 Account / Login",win)
        self.assertIn("Confirm-OllamaProfileMount",win)
        self.assertIn("'auth-help'",win)

if __name__=='__main__': unittest.main()
