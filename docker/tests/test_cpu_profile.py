import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('cpu_launcher', ROOT / 'launch_odysseus.py')
launcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launcher)


class CpuProfileTests(unittest.TestCase):
    def test_cpu_options_preserve_tools_images_and_output_budget(self):
        messages = [{'role': 'user', 'content': 'Read this image.', 'images': ['base64-image']}]
        tools = [{'type': 'function', 'function': {'name': 'diagnostic_ping'}}]
        original = {'model': launcher.CPU_MODEL, 'messages': messages, 'tools': tools,
                    'stream': True, 'think': True,
                    'options': {'num_ctx': 32768, 'num_gpu': 99, 'num_predict': 256, 'temperature': 0.7}}

        def builder(model):
            self.assertEqual(model, launcher.CPU_MODEL)
            return original

        payload = launcher.guard_builder(builder, '20m')(launcher.CPU_MODEL)
        self.assertIs(payload['think'], False)
        self.assertEqual(payload['keep_alive'], '20m')
        self.assertEqual(payload['options'], dict(num_ctx=4096, num_thread=2, num_gpu=0,
                                                 num_batch=128, num_predict=256, temperature=0.7))
        self.assertIs(payload['tools'], tools)
        self.assertIs(payload['messages'], messages)
        self.assertTrue(payload['stream'])
        self.assertTrue(original['think'])
        self.assertEqual(original['options']['num_ctx'], 32768)

    def test_other_models_and_unknown_builders(self):
        other = {'model': 'qwen3.5:4b', 'think': True, 'options': {'num_ctx': 8192}}
        guarded = launcher.guard_builder(lambda model: other)
        self.assertIs(guarded(model='qwen3.5:4b'), other)
        for builder in (None, lambda wrong_name: {}):
            with self.assertRaises(RuntimeError):
                launcher.guard_builder(builder)
        with self.assertRaises(RuntimeError):
            launcher.guard_builder(lambda model: {'unexpected': True})(launcher.CPU_MODEL)

    def test_launcher_installs_adapter_before_app_load_without_editing_source(self):
        with tempfile.TemporaryDirectory() as temp:
            app_root = Path(temp)
            (app_root / 'src').mkdir()
            (app_root / 'src' / '__init__.py').write_text('')
            source = 'def _build_ollama_payload(model, messages=None):\n    return {"model": model, "messages": messages, "stream": True}\n'
            core = app_root / 'src' / 'llm_core.py'
            core.write_text(source)
            (app_root / 'app.py').write_text('')
            (app_root / 'uvicorn.py').write_text(
                'import json\nfrom pathlib import Path\nfrom src import llm_core\n'
                'def run(app, **kwargs):\n'
                '    assert app == "app:app" and kwargs["workers"] == 1\n'
                '    payload = llm_core._build_ollama_payload("qwen3.5-zarzysseus-cpu:4b", [])\n'
                '    Path("captured.json").write_text(json.dumps(payload))\n')
            result = subprocess.run([sys.executable, str(ROOT / 'launch_odysseus.py'),
                                     '--app-root', temp], text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            payload = json.loads((app_root / 'captured.json').read_text())
            self.assertIs(payload['think'], False)
            self.assertEqual(payload['options']['num_thread'], 2)
            self.assertEqual(core.read_text(), source)


if __name__ == '__main__':
    unittest.main()
