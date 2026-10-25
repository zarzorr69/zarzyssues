"""The probe only inspects responses; it must never dispatch a tool."""
import importlib.util
from pathlib import Path
import unittest

FILE = Path(__file__).resolve().parents[2] / "scripts" / "zarzysseus_tool_call_probe.py"
spec = importlib.util.spec_from_file_location("z_tool_probe", FILE)
probe = importlib.util.module_from_spec(spec)
spec.loader.exec_module(probe)


class ToolCallProbeTests(unittest.TestCase):
    def test_select_canonical_ollama_name(self):
        names = ["qwen3-vl:8b", "hf.co/mradermacher/Dolphin-Mistral-24B-Venice-Edition-GGUF:Q4_K_M"]
        self.assertEqual(probe.resolve(names, "dolphin-mistral-24b-venice-edition"), names[1])
        self.assertEqual(probe.resolve(names, "QWEN3-VL:8B"), names[0])

    def test_ambiguous_model_does_not_guess(self):
        with self.assertRaises(ValueError):
            probe.resolve(["dolphin:a", "dolphin:b"], "dolphin")

    def test_openai_proposal(self):
        obj = {"choices": [{"message": {"tool_calls": [
            {"function": {"name": "probe_visit_page", "arguments": '{"url":"https://example.com"}'}}
        ], "content": None}}]}
        names, answer = probe.interpret(obj, "openai")
        self.assertEqual(names, ["probe_visit_page"])
        self.assertEqual(answer, "")

    def test_ollama_native_proposal(self):
        obj = {"message": {"tool_calls": [
            {"function": {"name": "probe_visit_page", "arguments": {"url": "https://example.com"}}}
        ]}}
        names, _ = probe.interpret(obj, "native")
        self.assertEqual(names, ["probe_visit_page"])

    def test_prose_is_not_tool_call(self):
        obj = {"choices": [{"message": {"content": "I will use the function now.",
                                        "tool_calls": []}}]}
        names, content = probe.interpret(obj, "openai")
        self.assertEqual(names, [])
        self.assertIn("I will", content)


if __name__ == "__main__":
    unittest.main()
