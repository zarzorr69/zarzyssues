from pathlib import Path
import hashlib, os, shutil, subprocess, sys, tempfile, unittest
ROOT=Path(__file__).resolve().parents[1]; SCRIPT=ROOT/'zarzysseus.sh'; KIT=ROOT/'docker'
class ModeTests(unittest.TestCase):
    def setUp(self):
        self.t=tempfile.TemporaryDirectory();self.addCleanup(self.t.cleanup); self.home=Path(self.t.name)
        self.env=dict(os.environ,HOME=str(self.home),ZARZYSSEUS_MODE_HOME=str(self.home/'config'),ZARZYSSEUS_DOCKER_DIR=str(KIT))
    def cmd(self,*args,env=None):
        return subprocess.run(['bash',str(SCRIPT),*args],env=env or self.env,cwd=self.home,capture_output=True,text=True,timeout=30)
    def test_modes(self):
        self.assertIn('not selected',self.cmd('mode','status').stdout)
        self.assertEqual(self.cmd('mode','docker').returncode,0)
        self.assertEqual((self.home/'config/runtime-mode').read_text(),'docker\n')
        self.assertEqual(self.cmd('mode','native').returncode,0)
        self.assertEqual((self.home/'config/runtime-mode').read_text(),'native\n')
        self.assertNotEqual(self.cmd('mode','nonsense').returncode,0)
    def test_sync_is_preview_and_preserves_configuration(self):
        existing=self.home/'kit';existing.mkdir()
        for name in ('compose.yaml','run.sh','zarzysseus-docker.sh'):shutil.copy2(KIT/name,existing/name)
        (existing/'compose.yaml').write_text('original compose\n')
        (existing/'.env').write_text('APP_BIND=0.0.0.0\nAPP_PORT=7012\n')
        env=dict(self.env,ZARZYSSEUS_DOCKER_DIR=str(existing))
        res=self.cmd('docker-kit-sync',env=env)
        self.assertEqual(res.returncode,0,res.stderr)
        self.assertEqual((existing/'compose.yaml').read_text(),'original compose\n')
        res=self.cmd('docker-kit-sync','apply',env=dict(env,ZARZYSSEUS_SYNC_CONFIRM='SYNC'))
        self.assertEqual(res.returncode,0,res.stderr)
        self.assertEqual((existing/'compose.yaml').read_bytes(),(KIT/'compose.yaml').read_bytes())
        self.assertEqual((existing/'.env').read_text(),'APP_BIND=0.0.0.0\nAPP_PORT=7012\n')
        self.assertEqual(len(list((existing/'.zarzysseus-kit-backups').rglob('compose.yaml'))),1)
        self.assertEqual((existing/'toolkit/zarzysseus.sh').read_bytes(),SCRIPT.read_bytes())
    def test_routing_with_stub_docker(self):
        bindir=self.home/'bin';bindir.mkdir(); log=self.home/'calls'
        docker=bindir/'docker'; docker.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "$DOCKER_TEST_LOG"\nexit 0\n');docker.chmod(0o755)
        env=dict(self.env,PATH=f'{bindir}:{os.environ.get("PATH","")}',DOCKER_TEST_LOG=str(log))
        self.assertEqual(self.cmd('mode','docker',env=env).returncode,0)
        res=self.cmd('help',env=env);self.assertEqual(res.returncode,0,res.stderr)
        self.assertIn('ZARZYSSEUS DOCKER',res.stdout)
        res=self.cmd('skills-search','literal $(not_executed)',env=env)
        self.assertEqual(res.returncode,0,res.stderr)
        self.assertIn('literal $(not_executed)',log.read_text())
        res=self.cmd('docker','system-update',env=env)
        self.assertEqual(res.returncode,2,res.stderr)
        self.assertIn('HOST-ONLY',res.stdout)
    def test_bundled_bridge(self):
        sys.path.insert(0,str(KIT));import zarzysseus_bridge as bridge
        data=SCRIPT.read_bytes()
        self.assertEqual((KIT/'toolkit/zarzysseus.sh').read_bytes(),data)
        self.assertEqual(hashlib.sha256(data).hexdigest(),bridge.SCRIPT_SHA256)
        adapted=bridge.adapt(data.decode())
        self.assertEqual(subprocess.run(['bash','-n'],input=adapted,text=True).returncode,0)
    def test_menu_parity_headings(self):
        data=(KIT/'zarzysseus-docker.sh').read_text()
        for label in ('INSTALL / UPDATE','SERVICE MANAGEMENT','MODEL RUNTIMES','MODEL MANAGER / HARDWARE FIT','OLLAMA MANAGEMENT','MLX-LM MANAGEMENT','HUGGING FACE / MODEL FILES','SKILLS.SH / AGENT SKILLS','MCP / FREEMCP','DIAGNOSTICS / TOOLS / ADVANCED','NETWORK DISCOVERABILITY','SWITCH TO NATIVE MODE'):
            self.assertIn(label,data)
if __name__=='__main__':unittest.main()
