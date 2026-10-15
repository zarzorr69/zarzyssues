"""V11.1 offline mode/profile and container-safety regression tests."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SH = ROOT / 'zarzysseus.sh'
KIT = ROOT / 'docker'

class ProfileTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.env = dict(os.environ, HOME=str(self.home), ZARZYSSEUS_MODE_HOME=str(self.home/'config'), ZARZYSSEUS_DOCKER_DIR=str(KIT))
        for v in ('ZARZYSSEUS_HARDWARE_PROFILE','ZARZYSSEUS_EXEC_MODE','ZARZYSSEUS_PROFILE'):
            self.env.pop(v, None)
    def runcli(self, *args, env=None):
        return subprocess.run(['bash',str(SH),*args], env=env or self.env, cwd=self.home, capture_output=True,text=True,timeout=30)
    def test_independent_persisted_profiles(self):
        self.assertIn('Native: full', self.runcli('profile','status').stdout)
        self.assertIn('Docker: cpu', self.runcli('profile','status').stdout)
        self.assertEqual(self.runcli('profile','native','cpu').returncode,0)
        self.assertEqual(self.runcli('profile','docker','full').returncode,0)
        out=self.runcli('profile','status').stdout
        self.assertIn('Native: cpu',out)
        self.assertIn('Docker: full',out)
        self.assertEqual((self.home/'config/hardware-native').read_text(),'cpu\n')
        self.assertEqual((self.home/'config/hardware-docker').read_text(),'full\n')
        self.assertNotEqual(self.runcli('profile','native','super').returncode,0)
        self.assertNotEqual(self.runcli('profile','windows','full').returncode,0)
    def test_profile_switch_preserves_mode_and_is_not_install(self):
        self.assertEqual(self.runcli('mode','docker').returncode,0)
        self.assertEqual(self.runcli('profile','full').returncode,0)
        self.assertEqual((self.home/'config/runtime-mode').read_text(),'docker\n')
        self.assertEqual((self.home/'config/hardware-docker').read_text(),'full\n')
    def test_cpu_native_gates_gpu_installs(self):
        self.runcli('profile','native','cpu')
        for action in ('accelerator-setup','sglang-install','vpull','install-auto-fit'):
            with self.subTest(action=action):
                res=self.runcli('native',action)
                self.assertEqual(res.returncode,2,(action,res.stdout,res.stderr))
                self.assertIn('CPU-only profile',res.stderr)
    def test_docker_cpu_and_full_profiles_routed(self):
        bindir=self.home/'bin'; bindir.mkdir()
        docker=bindir/'docker'
        docker.write_text('#!/bin/sh\necho "$*" >> "$DOCKER_TEST_LOG"\nexit 0\n'); docker.chmod(0o755)
        log=self.home/'calls'
        env=dict(self.env,PATH=f'{bindir}:{os.environ.get("PATH", "")}',DOCKER_TEST_LOG=str(log),ZARZYSSEUS_DOCKER_SUDO='0')
        self.runcli('profile','docker','cpu')
        res=self.runcli('docker','gpu-start',env=env)
        self.assertNotEqual(res.returncode,0)
        self.assertIn('CPU-only profile',res.stderr)
        self.assertNotIn('pull',log.read_text() if log.exists() else '')
        self.runcli('profile','docker','full')
        res=self.runcli('docker','profile',env=env)
        self.assertEqual(res.returncode,0,res.stderr)
        self.assertIn('full',res.stdout)
        res=self.runcli('docker','gpu-start',env=env)
        self.assertNotEqual(res.returncode,0)
        self.assertIn('ROCm GPU devices missing',res.stderr)
        self.assertNotIn('pull',log.read_text() if log.exists() else '')
    def test_checksum_and_gpu_overlay_present(self):
        import sys
        sys.path.insert(0,str(KIT)); import zarzysseus_bridge as bridge
        data=SH.read_bytes()
        self.assertEqual(hashlib.sha256(data).hexdigest(),bridge.SCRIPT_SHA256)
        self.assertEqual(data,(KIT/'toolkit/zarzysseus.sh').read_bytes())
        patch=bridge.adapt(data.decode())
        proc=subprocess.run(['bash','-n'],input=patch,text=True,capture_output=True)
        self.assertEqual(proc.returncode,0,proc.stderr)
        overlay=(KIT/'compose.gpu.yaml').read_text()
        for target in ('rdna3-sglang:','127.0.0.1:', 'rdna3-model-cache:', '/dev/kfd:', '/dev/dri:', 'profiles: [gpu]', 'sglang'):
            self.assertIn(target, overlay)
        self.assertNotIn('privileged: true',overlay)

if __name__=='__main__': unittest.main()
