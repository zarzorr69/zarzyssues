import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch as mock_patch

MODULE = Path(__file__).with_name("zarzysseus_restart_guard.py")
spec = importlib.util.spec_from_file_location("restart_guard", MODULE)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

PREFIX = '''#!/usr/bin/env bash
set -u
installation_complete() { return 0; }
install_odysseus() { :; }
info() { :; }
service_restart() { echo restarted; }
service_start() { echo started; }
service_enable() { echo enabled; }
install_chat_continuity_guard() { echo continuity; }
install_cookbook_reliability_fixes() { echo cookbook; }
install_direct_tool_json_recovery() { echo recovery; }
agent_reliability_auto_install() { echo repair; }
skills_mcp_autoprovision_all() { echo skills; }
ACTION="${1:-restart}"
case "$ACTION" in
'''
SUFFIX = '''    stop)
        echo stopped
        ;;
esac
'''

class GuardTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name)/"zarzysseus.sh"
        self.path.write_text(PREFIX + m.ORIGINAL + SUFFIX)
    def _call(self,*args):
        return m.main([*args,str(self.path)])
    def test_dry_run(self):
        before=self.path.read_bytes()
        self.assertEqual(self._call("dry-run"),0)
        self.assertEqual(self.path.read_bytes(),before)
    def test_apply_idempotent(self):
        old=self.path.read_bytes()
        new=m.patch(old)
        self.assertEqual(m.patch(new),new)
        m.syntax_check(new)
    def test_real_restart_does_not_repair(self):
        import subprocess
        m.syntax_check(m.patch(self.path.read_bytes()))
        self.path.write_bytes(m.patch(self.path.read_bytes()))
        res=subprocess.run(["bash",str(self.path),"restart"],text=True,capture_output=True)
        self.assertEqual(res.returncode,0,res.stderr)
        self.assertIn("restarted",res.stdout)
        for word in ["continuity","cookbook","recovery","repair","skills"]:
            self.assertNotIn(word+"\n",res.stdout)
    def test_start_still_provisions(self):
        import subprocess
        self.path.write_bytes(m.patch(self.path.read_bytes()))
        res=subprocess.run(["bash",str(self.path),"start"],text=True,capture_output=True)
        self.assertEqual(res.returncode,0,res.stderr)
        for word in ["continuity","cookbook","recovery","repair","skills","started"]:
            self.assertIn(word,res.stdout)
    def test_enable_still_provisions(self):
        import subprocess
        self.path.write_bytes(m.patch(self.path.read_bytes()))
        res=subprocess.run(["bash",str(self.path),"enable"],text=True,capture_output=True)
        self.assertEqual(res.returncode,0,res.stderr)
        self.assertIn("enabled",res.stdout)
        self.assertIn("repair",res.stdout)
    def test_unknown_source_refuses(self):
        with self.assertRaises(ValueError):m.patch(b"#!/bin/bash\necho hi\n")
    def test_unknown_marker_refuses(self):
        with self.assertRaises(ValueError):m.patch(b"#!/bin/bash\n"+m.MARKER.encode())
    def test_install_and_rollback(self):
        original=self.path.read_bytes()
        self.assertEqual(self._call("install"),0)
        self.assertNotEqual(original,self.path.read_bytes())
        self.assertEqual(self._call("status"),0)
        self.assertEqual(self._call("rollback"),0)
        self.assertEqual(original,self.path.read_bytes())
    def test_rollback_refuses_modified_source(self):
        self._call("install")
        self.path.write_bytes(self.path.read_bytes()+b"\n# changed\n")
        with self.assertRaises(ValueError):self._call("rollback")
    def test_missing_install_does_not_autoinstall_on_restart(self):
        import subprocess
        src=m.patch(self.path.read_bytes()).decode().replace("installation_complete() { return 0; }", "installation_complete() { return 1; }")
        self.path.write_text(src)
        res=subprocess.run(["bash",str(self.path),"restart"],text=True,capture_output=True)
        self.assertEqual(res.returncode,2)
        self.assertNotIn("restarted",res.stdout)
        self.assertIn("installation is incomplete",res.stderr)

if __name__ == "__main__":unittest.main()
