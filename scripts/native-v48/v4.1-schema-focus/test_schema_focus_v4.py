"""Offline synthetic agent contract tests for the guarded V4 patch."""
import ast
import importlib.util
from pathlib import Path
import unittest
import logging
import tempfile
import subprocess
import sys

PATH = Path(__file__).with_name('zarzysseus_schema_focus_v4.py')
spec = importlib.util.spec_from_file_location('schema_focus', PATH)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

NAV = 'mcp__builtin_browser__browser_navigate'
SHOT = 'mcp__builtin_browser__browser_take_screenshot'
CODE = 'mcp__builtin_browser__browser_run_code_unsafe'

def schema(name):
    return {'type': 'function', 'function': {'name': name, 'description': 'Test', 'parameters': {'type': 'object', 'properties': {}}}}

BASE = '''# ZARZYSSEUS_MCP_BARE_DOMAIN_V3
# ZARZYSSEUS_QWEN_EXPLICIT_TOOL_FOCUS_V4
# ZARZYSSEUS_SEAMLESS_MCP_RELEVANCE_V1

def agent(_last_user, messages, mcp_schemas, base_schemas, *, model="dolphin",
          relevant_tools=None, forced_tools=None, guide_only=False,
          _force_answer=False, plan_mode=False, exact_approval=None,
          tool_policy=None, disabled_tools=None, is_api_model=True,
          ody_qwen_finetune_model=False):
    disabled_tools = disabled_tools if disabled_tools is not None else set()
    def _zar_seamless_user_context(latest, history):
        if str(latest).lower() in ("now screenshot it", "css is fine", "yes", "do it", "go ahead"):
            old = [x["content"] for x in history if x.get("role") == "user" and x["content"] != latest]
            return "\\n".join(old[-3:]) + "\\n" + latest
        return latest
    def _filter_route_tool_schemas(schemas):
        return schemas
    def _tool_schemas_for_route(route_state):
        route_mcp_schemas = route_state["mcp_schemas"]
        route_relevant_tools = route_state["relevant_tools"]
        schemas = base_schemas
        if route_state["is_api_model"]:
            schemas = [s for s in base_schemas if s["function"]["name"] not in disabled_tools]
            # Qwen-only selector is already installed; V4 remains independent
            # ZARZYSSEUS_QWEN_EXPLICIT_TOOL_FOCUS_V4
            return _filter_route_tool_schemas(schemas)
        return _filter_route_tool_schemas(schemas)
    return _tool_schemas_for_route({"mcp_schemas": mcp_schemas, "relevant_tools": None,
                                   "is_api_model": is_api_model,
                                   "ody_qwen_finetune_model": ody_qwen_finetune_model})
'''

class FocusTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.patched = mod.apply_patch(BASE)
        scope = {'logger': logging.getLogger('test_v4')}
        exec(compile(cls.patched, '<synthetic-v4>', 'exec'), scope)
        cls.agent = staticmethod(scope['agent'])

    def test_source_patch_idempotent(self):
        self.assertEqual(mod.apply_patch(self.patched), self.patched)
        ast.parse(self.patched)
        self.assertEqual(self.patched.count(mod.MARKER), 1)

    def test_open_bare_domain_rag_fallback(self):
        offered = [schema(NAV), schema(SHOT), schema(CODE)]
        base = [schema('web_search'), schema('ask_user')]
        result = self.agent('Open example.com', [], offered, base)
        self.assertEqual([x['function']['name'] for x in result], [NAV])

    def test_https_and_dolphin_not_qwen(self):
        result = self.agent('Please open https://example.org', [], [schema(NAV)], [schema('web_search')], model='dolphin-mistral-24b')
        self.assertEqual([x['function']['name'] for x in result], [NAV])

    def test_shot_continuation(self):
        hist = [{'role':'user','content':'Open example.com'}, {'role':'assistant','content':'Navigated'}, {'role':'user','content':'Now screenshot it'}]
        result = self.agent('Now screenshot it', hist, [schema(NAV), schema(SHOT)], [schema('web_search')])
        self.assertEqual([x['function']['name'] for x in result], [SHOT])

    def test_css_continuation(self):
        hist = [{'role':'user','content':'Now screenshot it'}, {'role':'user','content':'CSS is fine'}]
        result = self.agent('CSS is fine', hist, [schema(SHOT)], [schema('web_search')])
        self.assertEqual([x['function']['name'] for x in result], [SHOT])

    def test_yes_continuation(self):
        hist = [{'role':'user','content':'Open example.com'}, {'role':'user','content':'Yes'}]
        result = self.agent('Yes', hist, [schema(NAV), schema(SHOT)], [schema('web_search')])
        self.assertEqual([x['function']['name'] for x in result], [NAV])

    def test_combined_navigate_and_screenshot(self):
        result = self.agent('Open example.com and take a screenshot', [], [schema(NAV),schema(SHOT),schema(CODE)], [schema('web_search')])
        self.assertEqual([x['function']['name'] for x in result], [NAV, SHOT])

    def test_no_mcp_inventory_no_bypass(self):
        base = [schema('web_search')]
        self.assertEqual(self.agent('Open example.com', [], [], base), base)

    def test_no_unrelated_focus(self):
        base = [schema('web_search'), schema('ask_user')]
        self.assertEqual(self.agent('Explain how browser caching works', [], [schema(NAV)], base), base)

    def test_negation(self):
        base = [schema('web_search')]
        self.assertEqual(self.agent("Don't open example.com", [], [schema(NAV)], base), base)
        self.assertEqual(self.agent('No, do not take a screenshot', [], [schema(SHOT)], base), base)

    def test_disabled_target(self):
        base = [schema('web_search')]
        self.assertEqual(self.agent('Open example.com', [], [schema(NAV)], base, disabled_tools={NAV}), base)

    def test_caller_scope_cannot_expand(self):
        base = [schema('web_search')]
        self.assertEqual(self.agent('Open example.com', [], [schema(NAV)], base, relevant_tools={'web_search'}), base)
        self.assertEqual(self.agent('Open example.com', [], [schema(NAV)], base, relevant_tools=set()), base)

    def test_skip_force_guide_plan_and_approval(self):
        base = [schema('web_search')]
        for kw in ({'forced_tools':[NAV]}, {'guide_only':True}, {'_force_answer':True}, {'plan_mode':True}, {'exact_approval':object()}, {'ody_qwen_finetune_model':True}, {'is_api_model':False}):
            with self.subTest(kw=kw):
                self.assertEqual(self.agent('Open example.com', [], [schema(NAV)], base, **kw), base)

    def test_tool_policy(self):
        base = [schema('web_search')]
        class Deny:
            block_all_tool_calls = False
            def blocks(self, name): return name == NAV
        class NoContract: pass
        class Broken:
            block_all_tool_calls = False
            def blocks(self, name): raise TypeError('bad contract')
        class BlockAll:
            block_all_tool_calls = True
            def blocks(self, name): return False
        for policy in (Deny(), NoContract(), Broken(), BlockAll()):
            with self.subTest(policy=type(policy).__name__):
                self.assertEqual(self.agent('Open example.com', [], [schema(NAV)], base, tool_policy=policy), base)

    def test_install_backup_status_and_safe_rollback(self):
        with tempfile.TemporaryDirectory() as root:
            src = Path(root) / 'odysseus' / 'src' / 'agent_loop.py'
            src.parent.mkdir(parents=True)
            src.write_text(BASE)
            def run(cmd):
                return subprocess.run([sys.executable, str(PATH), cmd, str(src)],
                                      text=True, capture_output=True)
            self.assertEqual(run('dry-run').returncode, 0)
            self.assertEqual(src.read_text(), BASE)
            self.assertEqual(run('install').returncode, 0)
            self.assertEqual(run('status').returncode, 0)
            self.assertEqual(run('dry-run').returncode, 0)
            self.assertEqual(run('install').returncode, 0)
            self.assertEqual(run('rollback').returncode, 0)
            self.assertEqual(src.read_text(), BASE)
            self.assertEqual(run('rollback').returncode, 2)

    def test_rollback_refuses_modified_source(self):
        with tempfile.TemporaryDirectory() as root:
            src = Path(root) / 'odysseus' / 'src' / 'agent_loop.py'
            src.parent.mkdir(parents=True)
            src.write_text(BASE)
            def run(cmd):
                return subprocess.run([sys.executable, str(PATH), cmd, str(src)],
                                      text=True, capture_output=True)
            self.assertEqual(run('install').returncode, 0)
            src.write_text(src.read_text() + '\n# custom later patch\n')
            self.assertEqual(run('rollback').returncode, 2)
            self.assertIn('custom later patch', src.read_text())

    def test_real_v3_legacy_return_prefix_overlap(self):
        # The real Odysseus V3 source has BOTH these return statements:
        # an indented API branch return and a less-indented legacy return.
        # Previous patch mistakenly counted the second inside the first.
        realistic = BASE
        self.assertEqual(realistic.count(mod.LEGACY_RETURN), 2)
        updated = mod.apply_patch(realistic)
        self.assertIn(mod.MARKER, updated)
        self.assertEqual(updated.count("schemas = _zar_focus_schemas_v4"), 1)
        ast.parse(updated)

    def test_scope_ignores_duplicate_legacy_return_outside_router(self):
        realistic = BASE
        # Another function is irrelevant to the tightly-scoped route guard.
        realistic += "\ndef unrelated(schemas):\n    if True:\n        return _filter_route_tool_schemas(schemas)\n"
        updated = mod.apply_patch(realistic)
        self.assertEqual(updated.count(mod.MARKER), 1)

    def test_guard_detects_double_router_legacy_return(self):
        realistic = BASE.replace(
            "        return _filter_route_tool_schemas(schemas)\n",
            "        return _filter_route_tool_schemas(schemas)\n"
            "        return _filter_route_tool_schemas(schemas)\n",
            1,
        )
        with self.assertRaisesRegex(ValueError, "route return layout"):
            mod.apply_patch(realistic)

    def test_source_refuses_unrecognized_layout(self):
        for bad in (BASE.replace('    def _tool_schemas_for_route(route_state):\n','',1),
                    BASE.replace('route_relevant_tools = route_state["relevant_tools"]','route_relevant_tools = []',1),
                    BASE.replace(mod.QWEN_MARKER, 'QWEN NOT PRESENT',1)):
            with self.subTest(source=bad[:100]):
                with self.assertRaises((SyntaxError,ValueError)):
                    mod.apply_patch(bad)

if __name__ == '__main__':
    unittest.main(verbosity=2)
