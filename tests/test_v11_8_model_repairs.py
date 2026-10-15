"""V11.8 offline-native endpoint and Docker /profiles repair contract tests."""
import os
from pathlib import Path
import socket
import sqlite3
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
DOCTOR = ROOT / "zarzysseus_model_endpoint_doctor_v11_8.py"


class NativeModelEndpointDoctor(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "data").mkdir()
        self.db = self.root / "data" / "app.db"
        conn = sqlite3.connect(self.db)
        conn.execute("CREATE TABLE model_endpoints (id TEXT PRIMARY KEY, name TEXT, base_url TEXT, is_enabled INTEGER, cached_models TEXT, pinned_models TEXT)")
        # Connect to ephemeral localhost service long enough to pick a valid port.
        with socket.socket() as s:
            s.bind(("127.0.0.1", 0))
            self.dead_port = s.getsockname()[1]
        self.id = "ep-tipsv2-g14"
        conn.execute("INSERT INTO model_endpoints VALUES (?,?,?,?,?,?)", (self.id,"tipsv2-g14",f"http://127.0.0.1:{self.dead_port}/v1",1,'["tipsv2-g14"]',None))
        conn.execute("INSERT INTO model_endpoints VALUES (?,?,?,?,?,?)", ("ep-ollama", "Local Ollama", "http://localhost:11434/v1",1,'["llama3.1:8b"]',None))
        conn.commit(); conn.close()

    def call(self, *args, input=None):
        return subprocess.run([sys.executable,str(DOCTOR),'--project',str(self.root),*args], input=input, text=True, capture_output=True, timeout=10,env={**os.environ,'DATABASE_URL':''})

    def rows(self):
        conn = sqlite3.connect(self.db)
        try: return dict(conn.execute('SELECT id,is_enabled FROM model_endpoints').fetchall())
        finally: conn.close()

    def test_audit_read_only_and_detects_nonchat(self):
        before = self.db.read_bytes()
        p = self.call()
        self.assertEqual(p.returncode,0,p.stderr)
        self.assertIn('[NON-CHAT MODEL CANDIDATE]',p.stdout)
        self.assertIn(self.id,p.stdout)
        self.assertEqual(self.db.read_bytes(),before)

    def test_disable_requires_confirmation(self):
        p = self.call('--disable-id',self.id)
        self.assertNotEqual(p.returncode,0)
        self.assertEqual(self.rows()[self.id],1)

    def test_disable_only_requested_id_and_backups(self):
        p=self.call('--disable-id',self.id,'--confirm','DISABLE')
        self.assertEqual(p.returncode,0,p.stderr)
        self.assertEqual(self.rows()[self.id],0)
        self.assertEqual(self.rows()['ep-ollama'],1)
        self.assertEqual(len(list(self.db.parent.glob('app.db.zarzysseus-endpoint-backup.*'))),1)

    def test_generic_offline_endpoint_cannot_be_modified(self):
        p=self.call('--disable-id','ep-ollama','--confirm','DISABLE')
        self.assertNotEqual(p.returncode,0)
        self.assertEqual(self.rows()['ep-ollama'],1)

    def test_mixed_chat_endpoint_cannot_be_disabled(self):
        conn=sqlite3.connect(self.db)
        conn.execute('UPDATE model_endpoints SET cached_models=? WHERE id=?', ('["tipsv2-g14", "llama3.1:8b"]', self.id))
        conn.commit();conn.close()
        p=self.call('--disable-id',self.id,'--confirm','DISABLE')
        self.assertNotEqual(p.returncode,0)
        self.assertEqual(self.rows()[self.id],1)

    def test_service_on_same_port_rejected(self):
        with socket.socket() as server:
            server.bind(('127.0.0.1',0));server.listen(1)
            conn=sqlite3.connect(self.db)
            conn.execute('UPDATE model_endpoints SET base_url=? WHERE id=?',(f'http://127.0.0.1:{server.getsockname()[1]}',self.id));conn.commit();conn.close()
            p=self.call('--disable-id',self.id,'--confirm','DISABLE')
            self.assertNotEqual(p.returncode,0)
            self.assertEqual(self.rows()[self.id],1)

    def test_native_menu_includes_doctor_and_approved_disable(self):
        script=(ROOT/'zarzysseus.sh').read_text()
        self.assertIn('INSPECT OFFLINE / UNSUPPORTED MODEL ENDPOINTS',script)
        self.assertIn('model-endpoint-disable',script)

    def test_docker_command_exposed(self):
        control=(ROOT/'docker/zarzysseus-docker.sh').read_text()
        self.assertIn('model-mount-check) kit_run mount-check "${1:-quality}"',control)
        self.assertIn('model-mount-repair) kit_run mount-repair "${1:-quality}"',control)
        self.assertIn('Repair Qwen Modelfile mount',control)


if __name__ == '__main__': unittest.main()
