"""Offline tests for V4.4 text-only screenshot handoff; no inference or tools."""
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import contextlib
import unittest

PATCH = Path(__file__).with_name("zarzysseus_image_handoff_v44.py")
spec = importlib.util.spec_from_file_location("v44", PATCH)
v44 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v44)

SOURCE = '''# ZARZYSSEUS_CONTEXT_CONTINUITY_V2
# ZARZYSSEUS_FORCED_ADDITIVE_FOCUS_V42
class Logger:
    def info(self, *_args, **_kw):
        pass
logger = Logger()
results_seen = []
def _append_tool_results(messages, round_response, converted_calls,
                         tool_results, tool_result_texts, used_native, round_num,
                         round_reasoning="", tool_result_records=None):
    results_seen.append((tool_result_texts, tool_result_records))
def agent_round(model, tool_result_records, tool_result_texts):
    messages = []
    round_response = ""
    converted_calls = []
    tool_results = []
    used_native = True
    round_num = 1
    round_reasoning = ""
    # Feed results back to LLM for next round
    _append_tool_results(messages, round_response, converted_calls,
                         tool_results, tool_result_texts, used_native, round_num,
                         round_reasoning=round_reasoning,
                         tool_result_records=tool_result_records)
    return results_seen[-1]
'''


def sample():
    return {"tool_name": "mcp__builtin_browser__browser_take_screenshot",
            "result": {"exit_code": 0, "images": [
                {"mimeType": "image/png", "data": "ZmFrZQ=="}],
                       "output": "Screenshot of viewport"},
            "content": '{"type":"png","scale":"css"}'}


def run(source, model, records, texts):
    ns = {}
    exec(compile(source, "<test-agent>", "exec"), ns)
    return ns["agent_round"](model, records, texts)


class HandoffTests(unittest.TestCase):
    def test_patch_compiles(self):
        compile(v44.patch_source(SOURCE), "<patched>", "exec")

    def test_removes_dolphin_image_model_side_only(self):
        r = sample()
        texts, records = run(v44.patch_source(SOURCE), "hf.co/.../Dolphin-Mistral-24B", [r], ["raw textual screenshot result"])
        self.assertNotIn("images", records[0]["result"])
        self.assertIs(records[0]["result"]["untrusted_content"], True)
        self.assertIn("browser_snapshot", texts[0])
        self.assertIn("images", r["result"])
        self.assertEqual(r["result"]["images"][0]["data"], "ZmFrZQ==")

    def test_failed_image_only_result_keeps_untrusted_gate(self):
        r = {"tool_name": "mcp__builtin_browser__browser_take_screenshot",
             "result": {"exit_code": 1, "images": [{"mimeType": "image/png", "data": "AA=="}]}}
        texts, records = run(v44.patch_source(SOURCE), "Dolphin-Mistral", [r], ["failed"])
        self.assertNotIn("images", records[0]["result"])
        self.assertEqual(records[0]["result"]["untrusted_content"], True)
        self.assertIn("browser_snapshot", texts[0])

    def test_dolphin_untouched_for_non_screenshot(self):
        r = {"tool_name": "mcp__builtin_browser__browser_snapshot", "result": {"output": "Example Domain"}}
        texts, records = run(v44.patch_source(SOURCE), "Dolphin-Mistral", [r], ["Example Domain"])
        self.assertEqual(records[0], r)
        self.assertEqual(texts, ["Example Domain"])

    def test_keeps_images_for_vision_capable_models(self):
        r = sample()
        texts, records = run(v44.patch_source(SOURCE), "qwen3-vl:8b", [r], ["screenshot"])
        self.assertEqual(records[0]["result"]["images"], r["result"]["images"])
        self.assertEqual(texts[0], "screenshot")

    def test_keeps_other_tool_images_even_on_dolphin(self):
        r = {"tool_name": "read_media", "result": {"images": [{"mimeType": "image/png", "data": "AA=="}]}}
        texts, records = run(v44.patch_source(SOURCE), "Dolphin-Mistral", [r], ["other"])
        self.assertIs(records[0], r)
        self.assertEqual(texts, ["other"])

    def test_many_results_alignment(self):
        r1 = {"tool_name": "web_fetch", "result": {"output": "ok"}}
        r2 = sample()
        r3 = {"tool_name": "mcp__builtin_browser__browser_snapshot", "result": {"output": "Example Domain"}}
        texts, records = run(v44.patch_source(SOURCE), "Dolphin-Mistral", [r1, r2, r3], ["fetch", "shot", "snapshot"])
        self.assertEqual(texts[0], "fetch")
        self.assertIn("pixels", texts[1])
        self.assertEqual(texts[2], "snapshot")
        self.assertIs(records[0], r1)
        self.assertIs(records[2], r3)

    def test_no_image_screenshot_untouched(self):
        r = {"tool_name": "mcp__builtin_browser__browser_take_screenshot", "result": {"exit_code": 1, "error": "timeout"}}
        texts, recs = run(v44.patch_source(SOURCE), "Dolphin-Mistral", [r], ["failed"])
        self.assertIs(recs[0], r)
        self.assertEqual(texts[0], "failed")

    def test_idempotent(self):
        once = v44.patch_source(SOURCE)
        self.assertEqual(once, v44.patch_source(once))

    def test_refuse_missing_marker(self):
        with self.assertRaisesRegex(ValueError, "Expected pre-existing"):
            v44.patch_source(SOURCE.replace("ZARZYSSEUS_FORCED_ADDITIVE_FOCUS_V42", "OTHER"))

    def test_refuse_missing_feedback(self):
        with self.assertRaisesRegex(ValueError, "exactly one"):
            v44.patch_source(SOURCE.replace("tool_result_records=tool_result_records", "tool_result_records=[]"))

    def test_refuse_duplicate_feedback(self):
        source = SOURCE.replace("    return results_seen[-1]", '''    _append_tool_results(messages, round_response, converted_calls,
                         tool_results, tool_result_texts, used_native, round_num,
                         round_reasoning=round_reasoning,
                         tool_result_records=tool_result_records)
    return results_seen[-1]''')
        with self.assertRaisesRegex(ValueError, "exactly one"):
            v44.patch_source(source)

    def test_backup_install_rollback(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            src = root / "src" / "agent_loop.py"
            src.parent.mkdir(parents=True)
            src.write_text(SOURCE)
            def call(action):
                from unittest.mock import patch
                with patch("sys.argv", ["v44", action, str(src)]), contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                    return v44.main()
            self.assertEqual(call("dry-run"), 0)
            self.assertEqual(src.read_text(), SOURCE)
            self.assertEqual(call("install"), 0)
            self.assertIn(v44.MARKER, src.read_text())
            self.assertEqual(call("status"), 0)
            self.assertEqual(call("rollback"), 0)
            self.assertEqual(src.read_text(), SOURCE)

    def test_rollback_guard_detects_modification(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            src = root / "src" / "agent_loop.py"
            src.parent.mkdir(parents=True)
            src.write_text(SOURCE)
            from unittest.mock import patch
            def call(action):
                with patch("sys.argv", ["v44", action, str(src)]), contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                    return v44.main()
            self.assertEqual(call("install"), 0)
            src.write_text(src.read_text() + "# modified\n")
            self.assertEqual(call("rollback"), 2)


if __name__ == "__main__":
    unittest.main()
