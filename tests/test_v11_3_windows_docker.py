"""Source contract tests for Windows Docker router; no Windows runtime is available in CI."""
import hashlib
import re
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]

class TestWindowsDockerIntegration(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.windows=(ROOT/'zarzysseus.ps1').read_text(encoding='utf-8-sig')
        cls.docker=(ROOT/'docker/zarzysseus-docker.ps1').read_text()
        cls.linux=(ROOT/'zarzysseus.sh').read_bytes()
        cls.linux_docker=(ROOT/'docker/zarzysseus-docker.sh').read_bytes()
        cls.readme=(ROOT/'README.md').read_text()
    def test_router_before_native_setup(self):
        self.assertLess(self.windows.index('if($Action -eq \'tui\' -and (ZZ-Mode)'),self.windows.index('$ProjectDir = Find-Project'))
        self.assertIn("ZZ-Store $ZZModeFile 'docker'",self.windows)
        self.assertIn("ZZ-Store $ZZModeFile 'native'",self.windows)
    def test_full_source_download_uses_explicit_approval(self):
        self.assertIn("Type DOWNLOAD",self.windows)
        self.assertIn('main.zip',self.windows)
        self.assertIn('Expand-Archive',self.windows)
        self.assertNotIn('Invoke-Expression',self.windows[:10000])
    def test_docker_requires_linux_containers_and_compose(self):
        self.assertIn('Docker Desktop',self.docker)
        self.assertIn('Linux containers',self.docker)
        self.assertIn('docker-prereq',self.docker)
        self.assertIn("Confirm 'INSTALL'",self.docker)
    def test_docker_uses_shared_agent_bridge(self):
        self.assertIn('zarzysseus_bridge.py',self.docker)
        for c in ['agent-doctor','skills-doctor','mcp-health','model-advisor','cookbook-fix','tool-json-fix','skills-setup']:
            self.assertIn(c,self.docker)
        self.assertIn('Confirm \'REPAIR\'',self.docker)
    def test_docker_model_download_requires_approval(self):
        self.assertIn('Confirm \'PULL\'',self.docker)
        self.assertIn('Confirm \'DOWN\'',self.docker)
        self.assertIn("'model-setup'",self.docker)
    def test_windows_docker_not_claim_amd_gpu(self):
        self.assertIn('RDNA3 /dev/kfd service is not supported',self.docker)
    def test_quickstarts_document_all_three(self):
        for h in ['Docker on regular Linux: curl one-liner','Docker on ZimaOS: curl one-liner','Docker on Windows: PowerShell curl.exe one-liner']:
            self.assertIn(h,self.readme)
        self.assertIn('install -d -o "$(id -un)"',self.readme)
        self.assertIn('main.zip',self.readme)
    def test_existing_linux_features_still_present(self):
        self.assertIn(b'agent-repair',self.linux)
        self.assertIn(b'gpu-dns-check',self.linux_docker)

if __name__=='__main__': unittest.main()
