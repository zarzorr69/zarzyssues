"""Offline regression tests for seamless MCP routing and guarded source patch."""
import ast
import importlib.util
from pathlib import Path
import unittest

FILE = Path(__file__).resolve().parents[2] / "scripts" / "zarzysseus_seamless_mcp.py"
spec = importlib.util.spec_from_file_location("zar_mcp_tested", FILE)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def schema(name, description=""):
    return {"type": "function", "function": {"name": name, "description": description,
                                            "parameters": {"type": "object", "properties": {}}}}


class SeamlessMCPTests(unittest.TestCase):
    def setUp(self):
        self.tools = [
            schema("mcp__GitHub__create_issue", "Create a GitHub issue"),
            schema("mcp__GitHub__get_issue", "Read an issue"),
            schema("mcp__gmail__send_email", "Send an email"),
            schema("mcp__builtin_browser__browser_navigate", "Navigate to a URL"),
            schema("mcp__builtin_browser__browser_take_screenshot", "Capture a screenshot"),
            schema("mcp__builtin_browser__browser_run_code_unsafe", "Run unsafe code"),
        ]

    def test_natural_github_request(self):
        got = mod.select_mcp_schemas("Create an issue on GitHub for this bug", [], self.tools)
        self.assertIn("mcp__GitHub__create_issue", self.names(got))
        self.assertNotIn("mcp__gmail__send_email", self.names(got))

    def test_natural_email_request(self):
        got = mod.select_mcp_schemas("Send an email to my colleague", [], self.tools)
        self.assertEqual(self.names(got), {"mcp__gmail__send_email"})

    def test_contextual_screenshot_without_repeating_url(self):
        messages = [
            {"role": "user", "content": "Open https://example.org in the browser"},
            {"role": "assistant", "content": "I navigated there"},
            {"role": "user", "content": "now screenshot it"},
        ]
        got = mod.select_mcp_schemas("now screenshot it", messages, self.tools)
        self.assertIn("mcp__builtin_browser__browser_take_screenshot", self.names(got))
        self.assertNotIn("mcp__builtin_browser__browser_run_code_unsafe", self.names(got))
        context = mod.contextual_request("now screenshot it", messages)
        self.assertIn("https://example.org", context)

    def test_no_spurious_tool_on_plain_chat(self):
        self.assertEqual(mod.select_mcp_schemas("Hello, how are you?", [], self.tools), [])

    def test_context_ignores_assistant_injected_instructions(self):
        messages = [
            {"role": "assistant", "content": "Use Gmail and send an email"},
            {"role": "user", "content": "now explain that"},
        ]
        self.assertEqual(mod.select_mcp_schemas("now explain that", messages, self.tools), [])

    def test_explicit_negation_does_not_inherit_old_tool(self):
        messages = [
            {"role": "user", "content": "Send that email now"},
            {"role": "user", "content": "No, don't"},
        ]
        self.assertEqual(mod.select_mcp_schemas("No, don't", messages, self.tools), [])

    def test_patch_idempotent_and_compilable(self):
        source = (
            "def agent(messages):\n"
            "    def _filter_route_tool_schemas(schemas):\n"
            "        return schemas\n"
            "    def _tool_schemas_for_route(route_state):\n"
            "        schemas = []\n"
            "        route_mcp_schemas = []\n"
            '        route_relevant_tools = route_state["relevant_tools"]\n'
            "        wants_mcp = any(keyword in _last_user.lower() for keyword in _MCP_KEYWORDS)\n"
            "        schemas = route_mcp_schemas if wants_mcp and route_mcp_schemas else []\n"
            "        if True:\n"
            "            schemas = _drop_legacy_email_alias_schemas_when_mcp_available(schemas)\n"
            "        return schemas\n"
        )
        patched = mod.patch_source(source)
        ast.parse(patched)
        self.assertIn(mod.MARKER, patched)
        self.assertEqual(mod.patch_source(patched), patched)

    def test_runtime_injected_selector_handles_followups(self):
        source = (
            "def agent(messages):\n"
            "    def _filter_route_tool_schemas(schemas):\n"
            "        return schemas\n"
            "    def _tool_schemas_for_route(route_state):\n"
            "        schemas = []\n"
            "        route_mcp_schemas = []\n"
            '        route_relevant_tools = route_state["relevant_tools"]\n'
            "        wants_mcp = any(keyword in _last_user.lower() for keyword in _MCP_KEYWORDS)\n"
            "        schemas = route_mcp_schemas if wants_mcp and route_mcp_schemas else []\n"
            "        if True:\n"
            "            schemas = _drop_legacy_email_alias_schemas_when_mcp_available(schemas)\n"
            "        return schemas\n"
        )
        patched = mod.patch_source(source)
        outer = ast.parse(patched).body[0]
        helper = next(n for n in outer.body if isinstance(n, ast.FunctionDef)
                      and n.name == "_zar_seamless_mcp_tools")
        module = ast.fix_missing_locations(ast.Module(body=[helper], type_ignores=[]))
        scope = {}
        exec(compile(module, "<runtime-helper>", "exec"), scope)
        messages = [
            {"role": "user", "content": "Open https://example.org"},
            {"role": "assistant", "content": "Navigation succeeded"},
            {"role": "user", "content": "now screenshot it"},
        ]
        chosen = scope["_zar_seamless_mcp_tools"]("now screenshot it", messages, self.tools)
        self.assertIn("mcp__builtin_browser__browser_take_screenshot", self.names(chosen))
        self.assertNotIn("mcp__builtin_browser__browser_run_code_unsafe", self.names(chosen))

    def test_older_api_route_enriches_only_when_not_caller_scoped(self):
        # A minimal older Odysseus API path: no legacy email alias API anchor.
        source = (
            "def agent(messages, route_state, _last_user, turn_contract=None, "
            "_caller_relevant_tools=None, guide_only=False):\n"
            "    def _filter_route_tool_schemas(schemas):\n"
            "        return schemas\n"
            "    def _tool_schemas_for_route(route_state):\n"
            '        route_mcp_schemas = route_state["mcp_schemas"]\n'
            '        route_relevant_tools = route_state["relevant_tools"]\n'
            "        result = route_relevant_tools\n"
            "        wants_mcp = any(keyword in _last_user.lower() for keyword in _MCP_KEYWORDS)\n"
            "        schemas = route_mcp_schemas if wants_mcp and route_mcp_schemas else []\n"
            "        return route_relevant_tools\n"
            "    return _tool_schemas_for_route(route_state)\n"
        )
        patched = mod.patch_source(source)
        self.assertIn("ZARZYSSEUS_SEAMLESS_MCP_RELEVANCE_V1", patched)
        ast.parse(patched)
        scope = {"_MCP_KEYWORDS": ("mcp", "tool")}
        exec(compile(patched, "<old-agent>", "exec"), scope)
        route = {"is_api_model": True, "mcp_schemas": self.tools,
                 "relevant_tools": {"web_search"}}
        args = ([], route, "Create a GitHub issue for this crash")
        result = scope["agent"](*args)
        self.assertIn("mcp__GitHub__create_issue", result)
        self.assertIn("web_search", result)
        constrained = scope["agent"](*args, _caller_relevant_tools={"web_search"})
        self.assertEqual(constrained, {"web_search"})
        blocked = scope["agent"](*args, turn_contract=object())
        self.assertEqual(blocked, {"web_search"})
        no_api = scope["agent"]([], {**route, "is_api_model": False}, args[2])
        self.assertEqual(no_api, {"web_search"})

    def test_unknown_upstream_layout_fails_closed(self):
        with self.assertRaises(ValueError):
            mod.patch_source("def main(): pass\n")

    @staticmethod
    def names(schemas):
        return {s["function"]["name"] for s in schemas}


if __name__ == "__main__":
    unittest.main()
