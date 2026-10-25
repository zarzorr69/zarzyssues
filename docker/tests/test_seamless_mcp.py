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

    def test_css_default_inherits_multi_turn_request(self):
        messages = [
            {"role": "user", "content": "Open https://example.org"},
            {"role": "assistant", "content": "Navigation completed"},
            {"role": "user", "content": "Now take a screenshot of that website"},
            {"role": "assistant", "content": "CSS or device scale?"},
            {"role": "user", "content": "CSS is fine"},
        ]
        context = mod.contextual_request("CSS is fine", messages)
        self.assertIn("https://example.org", context)
        self.assertIn("screenshot", context)
        schemas = mod.select_mcp_schemas("CSS is fine", messages, self.tools)
        self.assertIn("mcp__builtin_browser__browser_take_screenshot", self.names(schemas))

    def test_previous_chats_and_saved_memory_tool_hints(self):
        self.assertIn("search_chats", mod.relevant_memory_tools(
            "What did we decide in our previous chat about Zarzysseus?", []))
        self.assertIn("manage_memory", mod.relevant_memory_tools(
            "Remember this: always use fish in my Linux instructions", []))
        self.assertNotIn("manage_memory", mod.relevant_memory_tools(
            "Never remember or save this", []))
        self.assertEqual(mod.relevant_memory_tools("Hello", []), set())

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

    @staticmethod
    def legacy_agent_source():
        return (
            "def agent(messages, route_state, _last_user, relevant_tools=None, "
            "forced_tools=None, guide_only=False, _force_answer=False, "
            "tool_policy=None, disabled_tools=None):\n"
            "    disabled_tools = disabled_tools or set()\n"
            "    def _filter_route_tool_schemas(schemas):\n"
            "        return schemas\n"
            "    def _tool_schemas_for_route(route_state):\n"
            '        route_mcp_schemas = route_state["mcp_schemas"]\n'
            '        route_relevant_tools = route_state["relevant_tools"]\n'
            "        wants_mcp = any(keyword in _last_user.lower() for keyword in _MCP_KEYWORDS)\n"
            "        schemas = route_mcp_schemas if wants_mcp and route_mcp_schemas else []\n"
            "        return route_relevant_tools\n"
            "    return _tool_schemas_for_route(route_state)\n"
        )

    def test_patch_idempotent_and_compilable(self):
        patched = mod.patch_source(self.legacy_agent_source())
        ast.parse(patched)
        self.assertIn(mod.MARKER, patched)
        self.assertEqual(mod.patch_source(patched), patched)

    def test_runtime_injected_selector_handles_followups(self):
        patched = mod.patch_source(self.legacy_agent_source())
        outer = ast.parse(patched).body[0]
        helpers = [n for n in outer.body if isinstance(n, ast.FunctionDef)
                   and n.name in (
                       "_zar_seamless_user_context",
                       "_zar_seamless_memory_names",
                       "_zar_seamless_mcp_tools",
                   )]
        self.assertEqual(len(helpers), 3)
        module = ast.fix_missing_locations(ast.Module(body=helpers, type_ignores=[]))
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

    def test_legacy_api_route_permissions_and_caller_scope(self):
        patched = mod.patch_source(self.legacy_agent_source())
        scope = {"_MCP_KEYWORDS": ("mcp", "tool")}
        exec(compile(patched, "<legacy-agent>", "exec"), scope)
        agent = scope["agent"]
        route = {"is_api_model": True, "mcp_schemas": self.tools,
                 "relevant_tools": {"web_search"}}
        args = ([], route, "Create a GitHub issue for this crash")
        enabled = agent(*args)
        self.assertIn("mcp__GitHub__create_issue", enabled)
        self.assertIn("web_search", enabled)

        # When a caller explicitly chooses its tool surface, do not widen.
        self.assertEqual(agent(*args, relevant_tools={"web_search"}), {"web_search"})
        self.assertEqual(agent(*args, relevant_tools=set()), {"web_search"})
        self.assertEqual(agent(*args, forced_tools=["web_search"]), {"web_search"})
        self.assertEqual(agent(*args, guide_only=True), {"web_search"})
        self.assertEqual(agent(*args, _force_answer=True), {"web_search"})
        self.assertEqual(agent([], {**route, "is_api_model": False}, args[2]), {"web_search"})

        # Missing/unknown policy implementation and explicitly denied tools
        # must never be silently bypassed.
        self.assertEqual(agent(*args, tool_policy=object()), {"web_search"})
        class Policy:
            block_all_tool_calls = False
            def __init__(self, blocked=()):
                self.blocked = blocked
            def blocks(self, name):
                return name in self.blocked
        self.assertEqual(agent(*args, tool_policy=Policy({"mcp__GitHub__create_issue"}))
                         .intersection({"mcp__GitHub__create_issue"}), set())
        self.assertEqual(agent(*args, disabled_tools={"mcp__GitHub__create_issue"})
                         .intersection({"mcp__GitHub__create_issue"}), set())
        # Unknown policy contracts or malformed disabled collections fail closed.
        class BrokenPolicy:
            block_all_tool_calls = False
            def blocks(self, name):
                raise TypeError("unexpected policy call signature")
        self.assertEqual(agent(*args, tool_policy=BrokenPolicy()), {"web_search"})
        self.assertEqual(agent(*args, disabled_tools=1), {"web_search"})

        # Contextual follow-up should recover the previous user request.
        history = [
            {"role": "user", "content": "Open https://example.org in browser"},
            {"role": "assistant", "content": "Opened the page"},
            {"role": "user", "content": "now screenshot it"},
        ]
        result = agent(history, route, "now screenshot it")
        self.assertIn("mcp__builtin_browser__browser_take_screenshot", result)
        self.assertNotIn("mcp__builtin_browser__browser_run_code_unsafe", result)

    def test_missing_legacy_caller_scope_fails_closed(self):
        source = self.legacy_agent_source().replace("relevant_tools=None, ", "unsupported=None, ", 1)
        with self.assertRaisesRegex(ValueError, "relevant_tools"):
            mod.patch_source(source)

    def test_read_only_diagnosis_reports_guard_presence(self):
        from io import StringIO
        from contextlib import redirect_stdout
        source = (
            "def agent(messages):\n"
            "    def _filter_route_tool_schemas(schemas):\n"
            "        return schemas\n"
            "    def _tool_schemas_for_route(route_state):\n"
            '        route_relevant_tools = route_state["relevant_tools"]\n'
            "        return route_relevant_tools\n"
        )
        output = StringIO()
        with redirect_stdout(output):
            mod.diagnose_source(source)
        self.assertIn("turn_contract: 0 occurrence(s)", output.getvalue())
        self.assertIn("def _tool_schemas_for_route", output.getvalue())
        self.assertIn("No files modified", output.getvalue())

    def test_unknown_upstream_layout_fails_closed(self):
        with self.assertRaises(ValueError):
            mod.patch_source("def main(): pass\n")

    @staticmethod
    def names(schemas):
        return {s["function"]["name"] for s in schemas}


if __name__ == "__main__":
    unittest.main()
